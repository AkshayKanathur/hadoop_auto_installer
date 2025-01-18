This is a script to automate installation of single node hadoop on linux

Run the command  to install hadoop on your system automatically:
bash'''
chmod +x hadoop_auto_installer.sh

./hadoop_auto_installer.sh
'''
Tip: Sync ClusterID if incompatible ClusterID arise:

Update the clusterID in the DataNode's VERSION file to match the NameNode's clusterID.
