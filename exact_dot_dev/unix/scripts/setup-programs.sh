#!/env/bin/bash

sudo apt-get update
sudo apt-get install -y wget apt-transport-https software-properties-common

# Rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Powershell
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

sudo apt-get update

sudo apt-get install -y powershell

sudo apt-get install zoxide
sudo apt-get install fzf
sudo apt-get install fd-find
sudo apt-get install ripgrep

sudo add-apt-repository -y ppa:neovim-ppa/unstable
sudo apt-get install neovim

sudo apt-get install rclone
sudo apt-get install rsync
sudo apt-get install aria2
sudo apt-get install nmap
sudo apt-get install jq

sudo apt-get install build-essential
sudo apt-get install clang
sudo apt-get install cmake

sudo apt-get install unzip

sudo apt build-dep -y emacs
git clone --depth 1 https://github.com/emacs-mirror/emacs.git
cd emacs
./autogen
./configure
make -j5
sudo make install

# Missing:
cargo install sd
cargo install zoxide
cargo install watchexec-cli
cargo install git-delta
cargo install kalker
cargo install bat
cargo install exa
cargo install rnr
cargo install broot
cargo install mcfly
choco install ripgrep-all

wget https://github.com/muesli/duf/releases/download/v0.8.1/duf_0.8.1_linux_amd64.deb
sudo dpkg -i duf_0.8.1_linux_amd64.deb

git clone --depth 1 https://github.com/AstroNvim/AstroNvim ~/.config/nvim

curl -LO https://github.com/ClementTsang/bottom/releases/download/0.9.1/bottom_0.9.1_amd64.deb
sudo dpkg -i bottom_0.9.1_amd64.deb

cargo install gping


curl -SsL https://packages.httpie.io/deb/KEY.gpg | apt-key add -
curl -SsL -o /etc/apt/sources.list.d/httpie.list https://packages.httpie.io/deb/httpie.list
apt update
apt install httpie

cargo install httpie

difftastic
bind
fq

cargo install lsd
cargo install exa
go install github.com/cheat/cheat/cmd/cheat@latest

dotnet tool install -g git-credential-manager
git-credential-manager configure

dotnet tool install -g dotnet-script