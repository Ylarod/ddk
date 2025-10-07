FROM docker.cnb.cool/ylarod/ddk/ddk-builder:latest

ENV UV_INSTALL_DIR=/usr/local/bin

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip \
    zip unzip vim gnupg coreutils \
  && rm -rf /var/lib/apt/lists/*

# install vscode and extension
RUN curl -fsSL https://code-server.dev/install.sh | sh &&\
    code-server --install-extension cnbcool.cnb-welcome &&\
    code-server --install-extension redhat.vscode-yaml &&\
    code-server --install-extension waderyan.gitblame &&\
    code-server --install-extension mhutchie.git-graph &&\
    code-server --install-extension donjayamanne.githistory &&\
    code-server --install-extension cloudstudio.live-server &&\
    code-server --install-extension tencent-cloud.coding-copilot
    

# 安装 ssh 服务，用于支持 VSCode 客户端通过 Remote-SSH 访问开发环境，开发环境需保留 apt-get 缓存
RUN apt-get update && apt-get install -y wget unzip lsof nload htop net-tools dnsutils openssh-server zsh

# 安装 uv
RUN sh -c "$(curl -LsSf https://astral.sh/uv/install.sh)"

COPY .ide/scripts ./scripts

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    chmod +x ./scripts/*.sh && \
    ./scripts/add-zsh-plugins.sh zsh-autosuggestions zsh-syntax-highlighting && \
    ./scripts/set-zsh-env.sh && \
    echo 'setopt NO_AUTO_REMOVE_SLASH' >> /root/.zshrc && \
    chsh -s $(which zsh)

# 在最开始 source /etc/profile 
RUN sed -i '1isetopt NULL_GLOB 2>/dev/null\nsource /etc/profile\nunsetopt NULL_GLOB 2>/dev/null' $HOME/.zshrc

COPY .ide/settings.json /root/.vscode-server/data/Machine/settings.json
COPY .ide/settings.json /root/.local/share/code-server/Machine/settings.json
COPY .ide/gitconfig /root/.gitconfig

# 指定字符集支持命令行输入中文（根据需要选择字符集）
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8