module Api
  module V1
    class PaymentsController < ApplicationController
      rescue_from Idempotency::Executor::KeyReusedWithDifferentParamsError, with: :render_key_conflict
      rescue_from Idempotency::Lock::LockTimeoutError, with: :render_lock_timeout
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :render_invalid_record
      rescue_from ActionController::ParameterMissing, with: :render_parameter_missing

      before_action :require_idempotency_key!, only: :create

      # POST /api/v1/payments
      # Header: Idempotency-Key: <client-generated-uuid>
      def create
        executor = Idempotency::Executor.new(key: idempotency_key, fingerprint: fingerprint)

        result = executor.call do |idempotency_key_record|
          outcome = Payments::Processor.new(idempotency_key: idempotency_key_record, **payment_params.to_h.symbolize_keys).charge!
          status = outcome.success? ? 201 : 422
          [ status, PaymentSerializer.render(outcome.payment) ]
        end

        response.set_header("Idempotent-Replay", result.replayed.to_s)
        render json: result.body, status: result.status
      end

      # GET /api/v1/payments/:id
      def show
        payment = Payment.find(params[:id])
        render json: PaymentSerializer.render(payment)
      end

      private

      def idempotency_key
        request.headers["Idempotency-Key"]
      end

      def fingerprint
        Idempotency::RequestFingerprint.generate(
          method: request.method,
          path: request.path,
          params: payment_params.to_h
        )
      end

      def payment_params
        params.require(:payment).permit(:amount_cents, :currency, :description, :card_number)
      end

      def require_idempotency_key!
        return if idempotency_key.present?

        render json: {
          error: "missing_idempotency_key_header",
          message: "The Idempotency-Key header is required for this endpoint."
        }, status: :bad_request
      end

      def render_key_conflict(error)
        render json: { error: "idempotency_key_reused_with_different_params", message: error.message },
               status: :unprocessable_content
      end

      def render_lock_timeout(_error)
        render json: {
          error: "request_in_progress",
          message: "A request with this Idempotency-Key is already being processed. Please retry shortly."
        }, status: :conflict
      end

      def render_not_found
        render json: { error: "not_found" }, status: :not_found
      end

      def render_invalid_record(error)
        render json: { error: "invalid_payment", message: error.message }, status: :unprocessable_content
      end

      def render_parameter_missing(error)
        render json: { error: "invalid_request", message: error.message }, status: :bad_request
      end
    end
  end
end
