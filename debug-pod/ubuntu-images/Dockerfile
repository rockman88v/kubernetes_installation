FROM ubuntu:18.04
RUN apt update -y
RUN apt install -y telnet curl wget dnsutils net-tools
RUN apt-get install iputils-ping -y
CMD ["/bin/bash", "-c", "--", "while true; do sleep 30; done;"]
