FROM alpine
COPY hello-world.sh /app/hello-world.sh
COPY config/name.txt /app/config/name.txt
VOLUME /app/config
CMD ["sh","/app/hello-world.sh"]