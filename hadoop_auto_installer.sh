#!/bin/bash

# Error handler function
error_exit() {
    echo "An unexpected error occurred: $1"
    exit 1
}

# Prompt for user confirmation to proceed with Hadoop installation
echo "This script is to setup single node Hadoop."
read -p "Are you ready to install Hadoop? [y/N]: " confirmation
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    echo "Exiting the script. No changes made."
    exit 1
fi

# 1. Install Java 11
echo "Updating package list and installing Java 11..."
sudo dpkg --configure -a || error_exit "Failed to configure packages."
sudo apt-get update || error_exit "Failed to update package list."
sudo apt-get install -y openjdk-11-jdk || error_exit "Failed to install Java 11."

# 2. Download and Extract Hadoop (if not already downloaded)
HADOOP_VERSION="3.4.0"
HADOOP_TAR="hadoop-$HADOOP_VERSION.tar.gz"
HADOOP_DIR="/usr/local/hadoop"

if [ -f "$HOME/$HADOOP_TAR" ]; then
    echo "Hadoop tarball found in $HOME. Extracting..."
    sudo tar -xzvf "$HOME/$HADOOP_TAR" -C /usr/local/ || error_exit "Failed to extract Hadoop tarball from $HOME."
elif [ -f "$HOME/Downloads/$HADOOP_TAR" ]; then
    echo "Hadoop tarball found in Downloads. Extracting..."
    sudo tar -xzvf "$HOME/Downloads/$HADOOP_TAR" -C /usr/local/ || error_exit "Failed to extract Hadoop tarball from Downloads."
else
    echo "Hadoop tarball not found locally. Downloading from Apache..."
    wget "https://downloads.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/$HADOOP_TAR" -P "$HOME" || error_exit "Failed to download Hadoop tarball."
    sudo tar -xzvf "$HOME/$HADOOP_TAR" -C /usr/local/ || error_exit "Failed to extract downloaded Hadoop tarball."
fi

# Ensure the directory is moved and renamed to /usr/local/hadoop
echo "Moving and renaming Hadoop to $HADOOP_DIR..."
sudo mv "/usr/local/hadoop-$HADOOP_VERSION" "$HADOOP_DIR" || error_exit "Failed to move and rename Hadoop directory."

# 3. Configure Environment Variables
echo "Configuring Hadoop environment variables..."

SHELL_TYPE=$(basename "$SHELL")
echo "Detected shell type: $SHELL_TYPE"

# Function to configure environment variables in Bash
configure_bash() {
    BASHRC="$HOME/.bashrc"

    if ! grep -q "# Hadoop" "$BASHRC"; then
        echo "Adding Hadoop environment variables to $BASHRC..."
        cat <<EOL >>"$BASHRC"

# Hadoop
export HADOOP_HOME=$HADOOP_DIR
export HADOOP_INSTALL=\$HADOOP_HOME
export HADOOP_MAPRED_HOME=\$HADOOP_HOME
export HADOOP_COMMON_HOME=\$HADOOP_HOME
export HADOOP_HDFS_HOME=\$HADOOP_HOME
export YARN_HOME=\$HADOOP_HOME
export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_HOME/lib/native
export PATH=\$PATH:\$HADOOP_HOME/sbin:\$HADOOP_HOME/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

EOL
        echo "Hadoop environment variables added to $BASHRC."
    else
        echo "Hadoop environment variables already exist in $BASHRC."
    fi

    # Source the .bashrc to apply changes
    source "$BASHRC" || error_exit "Failed to source .bashrc."
}

# Function to configure environment variables in Fish
configure_fish() {
    FISH_CONFIG="$HOME/.config/fish/config.fish"

    if ! grep -q "# Hadoop" "$FISH_CONFIG"; then
        echo "Adding Hadoop environment variables to $FISH_CONFIG..."
        cat <<EOL >>"$FISH_CONFIG"

# Hadoop
if status --is-interactive
    set -x HADOOP_HOME $HADOOP_DIR
    set -x HADOOP_INSTALL \$HADOOP_HOME
    set -x HADOOP_MAPRED_HOME \$HADOOP_HOME
    set -x HADOOP_COMMON_HOME \$HADOOP_HOME
    set -x HADOOP_HDFS_HOME \$HADOOP_HOME
    set -x YARN_HOME \$HADOOP_HOME
    set -x HADOOP_COMMON_LIB_NATIVE_DIR \$HADOOP_HOME/lib/native
    set -x PATH \$PATH \$HADOOP_HOME/sbin \$HADOOP_HOME/bin
    set -x JAVA_HOME /usr/lib/jvm/java-11-openjdk-amd64
end

EOL
        echo "Hadoop environment variables added to $FISH_CONFIG."
    else
        echo "Hadoop environment variables already exist in $FISH_CONFIG."
    fi

    # Source the Fish configuration to apply changes
    fish -c "source $FISH_CONFIG" || error_exit "Failed to source Fish config."
}

# Apply configurations based on the detected shell
case "$SHELL_TYPE" in
bash)
    configure_bash
    ;;
fish)
    configure_fish
    ;;
*)
    echo "Unsupported shell: $SHELL_TYPE. Please configure manually."
    ;;
esac

# 4. Move pre-edited Hadoop configuration files
echo "Moving pre-edited Hadoop configuration files..."
if [ -d "hadoop_confs" ]; then
    sudo cp hadoop_confs/* /usr/local/hadoop/etc/hadoop/ || error_exit "Failed to copy Hadoop configuration files."
else
    echo "Directory hadoop_confs not found. Skipping file copy."
fi

# 5. Prompt for user_name with option to use $USER
echo ""
read -p "If the username is '$USER', press Enter. Otherwise, type your username: " input_user
echo ""
USER_NAME=${input_user:-$USER}
GROUP_NAME=$USER_NAME

# 6. Create HDFS Directories and Change Ownership
echo "Creating HDFS directories and changing ownership..."
sudo mkdir -p /usr/local/hadoop/hdfs/name || error_exit "Failed to create HDFS name directory."
sudo mkdir -p /usr/local/hadoop/hdfs/data || error_exit "Failed to create HDFS data directory."

# Check if group exists, create if it doesn't
if ! grep -q "^${GROUP_NAME}:" /etc/group; then
    echo "Group $GROUP_NAME does not exist. Creating group..."
    sudo groupadd "$GROUP_NAME" || error_exit "Failed to create group $GROUP_NAME."
else
    echo "Group $GROUP_NAME already exists."
fi

# Check if user is in group, add if necessary
if id -nG "$USER_NAME" | grep -qw "$GROUP_NAME"; then
    echo "User $USER_NAME is already in group $GROUP_NAME."
else
    echo "Adding user $USER_NAME to group $GROUP_NAME..."
    sudo usermod -aG "$GROUP_NAME" "$USER_NAME" || error_exit "Failed to add user $USER_NAME to group $GROUP_NAME."
fi

# Change ownership of HDFS directories
echo "Changing ownership of HDFS directories to $USER_NAME:$GROUP_NAME..."
sudo chown -R "$USER_NAME":"$GROUP_NAME" /usr/local/hadoop/hdfs/ || error_exit "Failed to change ownership of HDFS directories."
sudo chmod -R 755 /usr/local/hadoop/hdfs/ || error_exit "Failed to set permissions for HDFS directories."

# Creating logs directory and changing ownership
sudo mkdir -p /usr/local/hadoop/logs || error_exit "Failed to create logs directory."
sudo chown -R "$USER_NAME":"$GROUP_NAME" /usr/local/hadoop/logs/ || error_exit "Failed to change ownership of logs directory."
sudo chmod -R 755 /usr/local/hadoop/logs/ || error_exit "Failed to set permissions for logs directory."

# 7. SSH Setup for Hadoop
echo "Installing and setting up SSH for Hadoop..."
sudo apt update || error_exit "Failed to update packages for SSH."
sudo apt install -y openssh-server || error_exit "Failed to install OpenSSH server."

# Generate SSH keys only if not present
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa || error_exit "Failed to generate SSH keys."
else
    echo "SSH keys already exist. Skipping key generation."
fi

# Set permissions
chmod 700 ~/.ssh || error_exit "Failed to set permissions for .ssh directory."
cat ~/.ssh/id_rsa.pub >>~/.ssh/authorized_keys || error_exit "Failed to add public key to authorized_keys."
chmod 600 ~/.ssh/authorized_keys || error_exit "Failed to set permissions for authorized_keys."

# Starting ssh services
echo ""
read -p "Do you want to start SSH automatically when your system starts? [y/N] " confirmation
echo ""
if [[ "$confirmation" =~ ^[Yy]$ ]]; then
    echo "SSH will start automatically on boot."
    sudo systemctl enable ssh || error_exit "Failed to enable SSH to start on boot."
    echo ""
    echo "Run 'start-all.sh' next time when you want to start Hadoop."
    echo ""
    sleep 5
else
    echo "SSH will not start automatically."
    echo ""
    echo "Run 'sudo service ssh start && start-all.sh' next time when you want to start Hadoop."
    echo ""
    sleep 5
fi

sudo service ssh start

# 9. Start Hadoop Services
echo "Starting Hadoop services..."
/usr/local/hadoop/bin/hdfs namenode -format &&
    /usr/local/hadoop/sbin/start-dfs.sh &&
    /usr/local/hadoop/sbin/start-yarn.sh || error_exit "Failed to start Hadoop services."

# 10. Verify Installation
echo ""
echo "Hadoop installation completed. You can verify the installation by browsing:"
echo "HDFS: http://localhost:9870/"
echo "YARN: http://localhost:8088/"
echo ""
echo "Script execution completed!"
echo ""

case "$SHELL_TYPE" in
bash)
    bash
    ;;
fish)
    fish
    ;;
*)
    echo "Unsupported shell: $SHELL_TYPE. Please configure manually."
    ;;
esac
