local ChatChannel = {}

function ChatChannel:subscribed()
    -- Conecta ao stream do chat
    self:stream_from("chat_room")
end

function ChatChannel:speak(data)
    -- Envia a mensagem para todos no stream
    require("rio").broadcast("chat_room", { 
        user = data.user or "Anônimo",
        message = data.message
    })
end

return ChatChannel
