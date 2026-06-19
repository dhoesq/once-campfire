class Messages::ByBotsController < MessagesController
  allow_bot_access only: :create

  def create
    super
    # super renders head :forbidden for archived rooms (and room_not_found on a
    # missing room); only emit the created response when a message was actually
    # saved and nothing has been rendered yet.
    head :created, location: message_url(@message) if @message&.persisted? && !performed?
  end

  private
    def message_params
      if params[:attachment]
        params.permit(:attachment)
      else
        reading(request.body) { |body| { body: body } }
      end
    end

    def reading(io)
      io.rewind
      yield io.read.force_encoding("UTF-8")
    ensure
      io.rewind
    end
end
