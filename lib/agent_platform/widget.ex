defmodule AgentPlatform.Widget do
  @moduledoc """
  Generates embeddable chat widget JavaScript for client websites.

  Features:
  - Token-based authentication per agent
  - WebSocket connection for real-time chat
  - Configurable appearance and behavior
  - Mobile responsive widget
  - Conversation persistence via visitor_id
  """

  alias AgentPlatform.Agents.Agent

  def generate_embed_code(%Agent{} = agent) do
    base_url = AgentPlatformWeb.Endpoint.url()
    token = agent.widget_token
    config = agent.config || %{}

    """
    <!-- AgentPlatform Chat Widget -->
    <script>
    (function() {
      var AP_CONFIG = {
        token: '#{token}',
        baseUrl: '#{base_url}',
        agentName: '#{escape_js(agent.name)}',
        greeting: '#{escape_js(config["greeting"] || "Hello! How can I help you?")}',
        primaryColor: '#{config["primary_color"] || "#8b5cf6"}',
        position: '#{config["position"] || "bottom-right"}'
      };

      var visitorId = localStorage.getItem('ap_visitor_id');
      if (!visitorId) {
        visitorId = 'v_' + Math.random().toString(36).substr(2, 12) + Date.now().toString(36);
        localStorage.setItem('ap_visitor_id', visitorId);
      }

      function createWidget() {
        var container = document.createElement('div');
        container.id = 'ap-chat-widget';
        container.innerHTML = '<style>' +
          '#ap-chat-widget { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }' +
          '#ap-chat-toggle { position: fixed; bottom: 20px; ' + (AP_CONFIG.position === 'bottom-left' ? 'left' : 'right') + ': 20px; ' +
          'width: 60px; height: 60px; border-radius: 50%; background: ' + AP_CONFIG.primaryColor + '; ' +
          'border: none; cursor: pointer; box-shadow: 0 4px 12px rgba(0,0,0,0.3); z-index: 99999; ' +
          'display: flex; align-items: center; justify-content: center; transition: transform 0.2s; }' +
          '#ap-chat-toggle:hover { transform: scale(1.1); }' +
          '#ap-chat-toggle svg { width: 28px; height: 28px; fill: white; }' +
          '#ap-chat-window { position: fixed; bottom: 90px; ' + (AP_CONFIG.position === 'bottom-left' ? 'left' : 'right') + ': 20px; ' +
          'width: 380px; max-width: calc(100vw - 40px); height: 520px; max-height: calc(100vh - 120px); ' +
          'background: #fff; border-radius: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.2); ' +
          'display: none; flex-direction: column; overflow: hidden; z-index: 99998; }' +
          '#ap-chat-header { background: ' + AP_CONFIG.primaryColor + '; color: white; padding: 16px; ' +
          'display: flex; align-items: center; justify-content: space-between; }' +
          '#ap-chat-header h3 { margin: 0; font-size: 16px; font-weight: 600; }' +
          '#ap-chat-header .ap-close { background: none; border: none; color: white; font-size: 20px; cursor: pointer; padding: 4px; }' +
          '#ap-chat-messages { flex: 1; overflow-y: auto; padding: 16px; display: flex; flex-direction: column; gap: 12px; }' +
          '.ap-msg { max-width: 80%; padding: 10px 14px; border-radius: 12px; font-size: 14px; line-height: 1.5; word-wrap: break-word; }' +
          '.ap-msg-bot { background: #f3f4f6; align-self: flex-start; border-bottom-left-radius: 4px; }' +
          '.ap-msg-user { background: ' + AP_CONFIG.primaryColor + '; color: white; align-self: flex-end; border-bottom-right-radius: 4px; }' +
          '.ap-msg-typing { background: #f3f4f6; align-self: flex-start; padding: 12px 18px; }' +
          '.ap-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #999; margin: 0 2px; animation: apBounce 1.4s infinite ease-in-out; }' +
          '.ap-dot:nth-child(1) { animation-delay: 0s; }' +
          '.ap-dot:nth-child(2) { animation-delay: 0.2s; }' +
          '.ap-dot:nth-child(3) { animation-delay: 0.4s; }' +
          '@keyframes apBounce { 0%, 80%, 100% { transform: scale(0); } 40% { transform: scale(1); } }' +
          '#ap-chat-input-area { padding: 12px; border-top: 1px solid #e5e7eb; display: flex; gap: 8px; }' +
          '#ap-chat-input { flex: 1; border: 1px solid #d1d5db; border-radius: 8px; padding: 10px 12px; font-size: 14px; outline: none; resize: none; }' +
          '#ap-chat-input:focus { border-color: ' + AP_CONFIG.primaryColor + '; }' +
          '#ap-chat-send { background: ' + AP_CONFIG.primaryColor + '; color: white; border: none; border-radius: 8px; padding: 10px 16px; cursor: pointer; font-size: 14px; }' +
          '#ap-chat-send:disabled { opacity: 0.5; cursor: not-allowed; }' +
          '</style>' +
          '<button id="ap-chat-toggle" aria-label="Open chat">' +
          '<svg viewBox="0 0 24 24"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/></svg>' +
          '</button>' +
          '<div id="ap-chat-window">' +
          '<div id="ap-chat-header"><h3>' + AP_CONFIG.agentName + '</h3><button class="ap-close" aria-label="Close chat">&times;</button></div>' +
          '<div id="ap-chat-messages"></div>' +
          '<div id="ap-chat-input-area">' +
          '<input type="text" id="ap-chat-input" placeholder="Type a message..." autocomplete="off" />' +
          '<button id="ap-chat-send">Send</button>' +
          '</div></div>';

        document.body.appendChild(container);

        var toggle = document.getElementById('ap-chat-toggle');
        var chatWindow = document.getElementById('ap-chat-window');
        var closeBtn = container.querySelector('.ap-close');
        var input = document.getElementById('ap-chat-input');
        var sendBtn = document.getElementById('ap-chat-send');
        var messages = document.getElementById('ap-chat-messages');
        var isOpen = false;
        var conversationId = null;

        toggle.addEventListener('click', function() {
          isOpen = !isOpen;
          chatWindow.style.display = isOpen ? 'flex' : 'none';
          if (isOpen && messages.children.length === 0) {
            addMessage(AP_CONFIG.greeting, 'bot');
          }
          if (isOpen) input.focus();
        });

        closeBtn.addEventListener('click', function() {
          isOpen = false;
          chatWindow.style.display = 'none';
        });

        input.addEventListener('keydown', function(e) {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
          }
        });

        sendBtn.addEventListener('click', sendMessage);

        function addMessage(text, role) {
          var div = document.createElement('div');
          div.className = 'ap-msg ap-msg-' + role;
          div.textContent = text;
          messages.appendChild(div);
          messages.scrollTop = messages.scrollHeight;
        }

        function showTyping() {
          var div = document.createElement('div');
          div.className = 'ap-msg ap-msg-typing';
          div.id = 'ap-typing';
          div.innerHTML = '<span class="ap-dot"></span><span class="ap-dot"></span><span class="ap-dot"></span>';
          messages.appendChild(div);
          messages.scrollTop = messages.scrollHeight;
        }

        function hideTyping() {
          var el = document.getElementById('ap-typing');
          if (el) el.remove();
        }

        function sendMessage() {
          var text = input.value.trim();
          if (!text) return;

          addMessage(text, 'user');
          input.value = '';
          sendBtn.disabled = true;
          showTyping();

          fetch(AP_CONFIG.baseUrl + '/api/chat/' + AP_CONFIG.token, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              message: text,
              visitor_id: visitorId,
              conversation_id: conversationId,
              channel: 'widget'
            })
          })
          .then(function(r) { return r.json(); })
          .then(function(data) {
            hideTyping();
            sendBtn.disabled = false;
            if (data.conversation_id) conversationId = data.conversation_id;
            if (data.response) addMessage(data.response, 'bot');
            if (data.error) addMessage('Sorry, something went wrong. Please try again.', 'bot');
          })
          .catch(function() {
            hideTyping();
            sendBtn.disabled = false;
            addMessage('Connection error. Please try again.', 'bot');
          });
        }
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', createWidget);
      } else {
        createWidget();
      }
    })();
    </script>
    """
  end

  def generate_widget_js(%Agent{} = agent) do
    generate_embed_code(agent)
  end

  defp escape_js(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "")
  end

  defp escape_js(_), do: ""
end
