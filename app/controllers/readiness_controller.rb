class ReadinessController < ApplicationController
  def show
    checks = DependencyReadiness.new.call
    ready = checks.values.all? { |value| value == "ok" }
    response.set_header("Cache-Control", "no-store")
    render json: { status: ready ? "ready" : "not_ready", checks: checks },
           status: ready ? :ok : :service_unavailable
  end
end
