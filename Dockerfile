
FROM ubuntu:20.04

ARG DOCKER_USER
ARG DOCKER_UID
ARG DOCKER_GID

RUN apt update && \
    apt upgrade -y && \
    apt install -y \
        sudo \
        curl

# Create a non-root user
RUN echo "$DOCKER_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# Use exit command to ignore error if group already exists.
RUN groupadd --gid=$DOCKER_GID $DOCKER_USER; exit 0
RUN useradd --uid=$DOCKER_UID --gid=$DOCKER_GID -m --groups sudo $DOCKER_USER
USER $DOCKER_USER
WORKDIR /home/$DOCKER_USER

# Install Ghostscript
RUN curl -L https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs952/ghostscript-9.52-linux-x86_64.tgz -O
RUN tar xf ghostscript-9.52-linux-x86_64.tgz
RUN sudo mv ghostscript-9.52-linux-x86_64/gs-952-linux-x86_64 /usr/local/bin/gs
RUN rm -rf ghostscript-9.52-linux-x86_64*

# Install Xpdf
RUN sudo apt install -y libfontconfig1
RUN curl https://dl.xpdfreader.com/xpdf-tools-linux-4.03.tar.gz -O
RUN tar xf xpdf-tools-linux-4.03.tar.gz
RUN sudo mv xpdf-tools-linux-4.03/bin64/pdftotext /usr/local/bin/
RUN rm -rf xpdf-tools-linux-4.03*

# Install Ruby via RVM and bundler and jekyll gems.
# https://rvm.io/rvm/install#1-download-and-run-the-rvm-installation-script
RUN sudo apt install -y gnupg2

# do this thing for Docker: https://rvm.io/rvm/security#ipv6-issues
RUN mkdir ~/.gnupg && \
    chmod 700 ~/.gnupg && \
    echo "disable-ipv6" > ~/.gnupg/dirmngr.conf

RUN gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
RUN curl -sSL https://get.rvm.io | bash -s stable --ruby

WORKDIR /home/$DOCKER_USER/collectionbuilder
RUN sudo chown $DOCKER_USER:$DOCKER_GID .
COPY Gemfile .
RUN /bin/bash -c "source ~/.rvm/scripts/rvm && \
    rvm install 2.7.0 && \
    rvm use 2.7.0 --default && \
    gem install bundler -v 2.1.4 && \
    bundle install"
RUN echo 'source "$HOME/.rvm/scripts/rvm"' >> $HOME/.bashrc

# Install nvm for building the search app
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
RUN /bin/bash -i -c 'nvm install --default v13.8.0'

CMD ["/bin/bash", "--login"]
