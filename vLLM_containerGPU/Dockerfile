# vLLM generic runner
FROM vllm/vllm-openai:latest

# Put entrypoint in PATH and make it executable
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

