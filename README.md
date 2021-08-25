# CollectionBuilder-Elasticsearch

CollectionBuilder-Elasticsearch is a web application generator and toolset for configuring, administering, and searching collection data using Elasticsearch.

## Set Up Your Development Environment

You can either build the Docker image that has all of the software dependencies preinstalled, or you can install these dependencies yourself on your own machine.

### Use Docker

#### Build the image

If you have `make` installed::
```
make build-docker-image
```

otherwise, you can run the `docker-compose` command directly:
```
docker-compose build \
	--build-arg "DOCKER_USER=`id -un`" \
	--build-arg "DOCKER_UID=`id -u`" \
	--build-arg "DOCKER_GID=`id -g`" \
	default
```

#### Run the container

Running the container will give you a bash prompt within the container at which you can execute the steps in <a href="#building-the-project">Building The Project</a>. Note that `docker-compose` will automatically create a local Elasticseach instance so you can skip step `2. Start Elasticsearch`.

The `docker-compose` configuration will mirror your local `collectionbuilder-elasticsearch` directory inside the container so any changes you make to the files in that directory on your local filesystem will be reflected within the container.

If using `make`:
```
make run-docker-image
```

otherwise:
```
docker-compose run default
```


### Install the dependencies yourself / the non-Docker option

#### Ruby and Gems

See: https://collectionbuilder.github.io/docs/software.html#ruby

The code in this repo has been verified to work with the following versions:

| name | version |
| --- | --- |
| ruby | 2.7.0 |
| bundler | 2.1.4 |
| jekyll | 4.1.0 |

After the `bundler` gem is installed, run the following command to install the remaining dependencies specified in the `Gemfile`:

```
bundle install
```

#### Install the Required Software Dependencies

*Note for MAC Users: Several dependencies can be installed using [Homebrew](https://brew.sh/). Homebrew makes the installation simple via basic command line instructions like `brew install xpdf`

##### Xpdf 4.02
The `pdftotext` utility in the Xpdf package is used by `extract-pdf-text` to extract text from `.pdf` collection object files.

Download the appropriate executable for your operating system under the "Download the Xpdf command line tools:" section here: http://www.xpdfreader.com/download.html

The scripts expect this to be executable via the command `pdftotext`.

**Windows**  users will need to extract the files from the downloaded .zip folder and then move the extracted directory to their program files folder.

**Mac** users can use Homebrew and type `brew install xpdf` into the command line.

Here's an example of installation under Ubuntu:
```
curl https://xpdfreader-dl.s3.amazonaws.com/xpdf-tools-linux-4.02.tar.gz -O
tar xf xpdf-tools-linux-4.02.tar.gz
sudo mv xpdf-tools-linux-4.02/bin64/pdftotext /usr/local/bin/
rm -rf xpdf-tools-linux-4.02*
```

##### Elasticsearch 7.7.0<a id="elasticsearch-installation"></a>
Download the appropriate executable for your operating system here: https://www.elastic.co/downloads/elasticsearch

**Windows**  users will need to extract the files from the downloaded .zip folder and then move the extracted directory to their program files folder.

**Mac** users can use homebrew. Following [these instructions]
(https://www.elastic.co/guide/en/elasticsearch/reference/current/brew.html) --> Type `brew tap elastic/tap` into your terminal "to tap the Elastic Homebrew repository." Then type `brew install elastic/tap/elasticsearch-full` to install the full version.


Here's an example of installation under Ubuntu:
```
curl https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.7.0-amd64.deb -O
curl https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.7.0-amd64.deb.sha512 -O
sha512sum -c elasticsearch-7.7.0-amd64.deb.sha512
sudo dpkg -i elasticsearch-7.7.0-amd64.deb
```

###### Configure Elasticsearch

***For Mac and Linux Users***

Add the following lines to your `elasticsearch.yml` configuration file:

```
network.host: 0.0.0.0
discovery.type: single-node
http.cors.enabled: true
http.cors.allow-origin: "*"
```

Following the above installation for Ubuntu, `elasticsearch.yml` can be found in the directory `/etc/elasticsearch`

**Mac** users can find `elasticsearch.yml` in the directory `/usr/local/etc/elasticsearch/`

###### Update `_config.yml`
Update [\_config.yml](https://github.com/CollectionBuilder/collectionbuilder-sa_draft/blob/master/_config.yml#L17-L21) to reflect your Elasticsearch server configuration. E.g.:
```
elasticsearch-protocol: http
elasticsearch-host: 0.0.0.0
elasticsearch-port: 9200
elasticsearch-index: moscon_programs_collection
```

***For Windows Users***

Add the following lines to your `elasticsearch.yml` configuration file:

```
network.host: localhost
discovery.type: single-node
http.cors.enabled: true
http.cors.allow-origin: "*"
```

Following the above installation for Ubuntu, `elasticsearch.yml` can be found in the directory `/etc/elasticsearch`

###### Update `_config.yml`
Update [\_config.yml](https://github.com/CollectionBuilder/collectionbuilder-sa_draft/blob/non-docker/_config.yml#L17-L21) to reflect your Elasticsearch server configuration. E.g.:
```
elasticsearch-protocol: http
elasticsearch-host: localhost
elasticsearch-port: 9200
elasticsearch-index: moscon_programs_collection
```


<span name="building-the-project"></span>
## Building the Project

### 1. Configure your collections

Add the collections you want to include in the build to the [config-collections.csv](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/main/_data/config-collections.csv) configuration file. Each row must specify at least a `homepage_url` value. Any unspecified fields will be addressed during the build process, either automatically or via a manual input prompt.


### 2. Start Elasticsearch

Though this step is platform dependent, you might accomplish this by executing `elasticsearch` in a terminal.

For example, if you [installed Elasticsearch under Ubuntu](#elasticsearch-installation), you can start Elasticsearch with the command:

```
sudo service elasticsearch start
```

### 3. Build the project

Use the [cb:build](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/collectionbuilder.rake#L773) rake task to automatically execute the following rake tasks:

1. `cb:generate_collections_metadata`
2. `cb:download_collections_objects_metadata`
3. `cb:analyze_collections_objects_metadata`
4. `cb:generate_search_config`
5. `cb:download_collections_pdfs`
6. `cb:extract_pdf_text`
7. `cb:generate_collections_search_index_data`
8. `cb:generate_collections_search_index_settings`
9. `es:create_directory_index`
10. `cb:create_collections_search_indices`
11. `cb:load_collections_search_index_data`

Usage:

```
rake cb:build
```

See [Manually building the project](#manually-building-the-project) for information on how to customize these build steps.


### 4. Adjust Your Search Configuration

`_data/config-search.csv` defines the settings for the fields that you want indexed and displayed in search. This configuration file is automatically generated
during the build process via analysis of the collection object metadata by the [generate_search_config](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/collectionbuilder.rake#L348) rake task. While the auto-generated config is a good starting point, we recommend that you audit and edit this file to refine the search experience.


### 5. Start the Development Server
```
rake cb:serve
```


## The Rake Tasks

[rake](https://ruby.github.io/rake/) tasks are used to automate project build steps and administer the Elasticsearch instance.

All of the defined rake tasks, as reported by `rake --tasks`:

```
rake cb:analyze_collections_objects_metadata                                     # Analyze the downloaded collection object metadata files
rake cb:build[env,test]                                                          # Execute all build steps required to go from a config-collection file to fully-populated Elasticsearch index
rake cb:create_collections_search_indices[env,es_profile]                        # Create Elasticsearch indices all configured collections
rake cb:deploy                                                                   # Build site with production env
rake cb:download_collections_objects_metadata                                    # Download the object metadata files for each collection
rake cb:download_collections_pdfs[test]                                          # Download collections PDFs for text extraction
rake cb:enable_daily_search_index_snapshots[profile]                             # Enable daily Elasticsearch snapshots to be written to the "_elasticsearch_snapshots" directory of your Digital Ocean Space
rake cb:extract_pdf_text                                                         # Extract the text from PDF collection objects
rake cb:generate_collection_search_index_data[env,collection_url]                # Generate the file that we'll use to populate the Elasticsearch index via the Bulk API
rake cb:generate_collection_search_index_settings[collection_url]                # Generate the settings file that we'll use to create the Elasticsearch index
rake cb:generate_collections_metadata                                            # Generate metadata for each collection from local config and remote JSON-LD
rake cb:generate_collections_search_index_data[env]                              # Generate the file that we'll use to populate the Elasticsearch index via the Bulk API for all configured collections
rake cb:generate_collections_search_index_settings[env]                          # Generate the Elasticsearch index settings files for all configured collections
rake cb:generate_search_config                                                   # Create an initial search config from the superset of all object fields
rake cb:load_collections_search_index_data[env,es_profile]                       # Load data into Elasticsearch indices for all configured collections
rake cb:serve[env]                                                               # Run the local web server
rake es:create_directory_index[profile]                                          # Create the Elasticsearch directory index
rake es:create_index[profile,index,settings_path]                                # Create the Elasticsearch index
rake es:create_snapshot[profile,repository,wait]                                 # Create a new Elasticsearch snapshot
rake es:create_snapshot_policy[profile,policy,repository,schedule]               # Create a policy to enable automatic Elasticsearch snapshots
rake es:create_snapshot_s3_repository[profile,bucket,base_path,repository_name]  # Create an Elasticsearch snapshot repository that uses S3-compatible storage
rake es:delete_directory_index[profile]                                          # Delete the Elasticsearch directory index
rake es:delete_index[profile,index]                                              # Delete the Elasticsearch index
rake es:delete_snapshot[profile,snapshot,repository]                             # Delete an Elasticsearch snapshot
rake es:delete_snapshot_policy[profile,policy]                                   # Delete an Elasticsearch snapshot policy
rake es:delete_snapshot_repository[profile,repository]                           # Delete an Elasticsearch snapshot repository
rake es:execute_snapshot_policy[profile,policy]                                  # Manually execute an existing Elasticsearch snapshot policy
rake es:list_indices[profile]                                                    # Pretty-print the list of existing indices to the console
rake es:list_snapshot_policies[profile]                                          # List the currently-defined Elasticsearch snapshot policies
rake es:list_snapshot_repositories[profile]                                      # List the existing Elasticsearch snapshot repositories
rake es:list_snapshots[profile,repository_name]                                  # List available Elasticsearch snapshots
rake es:load_bulk_data[profile,datafile_path]                                    # Load index data using the Bulk API
rake es:minimize_disk_watermark[profile]                                         # Minimize the disk watermark to allow write operations on a near-full disk
rake es:ready[profile]                                                           # Display whether the Elasticsearch instance is up and running
rake es:restore_snapshot[profile,snapshot_name,wait,repository_name]             # Restore an Elasticsearch snapshot
rake es:update_directory_index[profile,raise_on_missing]                         # Update the Elasticsearch directory index to reflect the current indices
```


### Details

You can find detailed information about many of these tasks in the section: [Manually building the project](#manually-building-the-project)


### Definitions

All rake tasks are defined by the `.rake` files in the [rakelib/](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/tree/main/rakelib) directory. Note that the empty (less a comment justifying its existence) `Rakefile` in the project root exists only to signal to rake that it should look for tasks in `rakelib/`.

The currently defined `.rake` files are as follows:

| file | description |
| --- | --- |
| [collectionbuilder.rake](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/main/rakelib/collectionbuilder.rake) | Single-operation project build tasks |
| [elasticsearch.rake](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/main/rakelib/elasticsearch.rake) | Elasticsearch administration tasks |


### Customization

You can customize many of the default task configuration options by modifying the values in [rakelib/lib/constants.rb](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/main/rakelib/lib/constants.rb)


### External Dependencies

Some tasks have external dependencies as indicated below:

| task name | software dependencies | service dependencies |
| --- | --- | --- |
| cb:extract_pdf_text | xpdf | |
| es:* | | Elasticsearch |



## Deploy a Production Elasticsearch Instance on a Digital Ocean Droplet

This section will describe how to get Elasticsearch up and running on a Digital Ocean Droplet using our preconfigured, custom disk image.

1. Import our custom Elasticsearch image via the Digital Ocean web console by navigating to:

    ```
    Images -> Custom Images -> Import via URL
    ```

    and entering the URL: https://collectionbuilder-sa-demo.s3.amazonaws.com/collectionbuilder-elasticsearch-1-0.vmdk

    ![do_custom_image_import](https://user-images.githubusercontent.com/585182/87325500-8678f500-c4ff-11ea-9a70-e65b437b4c20.gif)

- You will need to select a "Distribution" -- Choose `Ubuntu`.
- You will need to select a distribution center location. Choose the location closest to your physical location.

2. Once the image is available within your account, click on `More -> Start a droplet`

- You can simply leave the default settings and scroll to the bottom of the page to start this.

3. Once the Droplet is running, navigate to:

    ```
    Networking -> Firewalls -> Create Firewall
    ```

    Give the firewall a name and add the rules as depicted in the below screenshot:

    ![Screenshot from 2020-07-13 12-05-32](https://user-images.githubusercontent.com/585182/87326758-2c792f00-c501-11ea-9a82-45977a8c7582.png)

    - The `HTTP TCP 80` rule allows the `certbot` SSL certificate application that we'll soon run to verify that we own this machine.

    - The `Custom TCP 9200` rule enables external access to the Elasticsearch instance.

    In the `Apply to Droplets` section, specify the name of the previously-created Elasticsearch Droplet and click `Create Firewall`

    This can be found at the top of the page for the firewall. There is a `droplets` menu option (it's a little hard to see). Click that and then specifiy the name of the droplet you created.

4. Generate your SSL certificate

    The Elasticsearch server is configured to use secure communication over HTTPS, which requires an SSL certificate. In order to request a free SSL certificate from Let's Encrypt, you first need to ensure that your Elasticsearch server is accessible via some registered web domain. To do this, you'll need to create a `A`-type DNS record that points some root/sub-domain to the IP address of your Droplet.

    1. Create a DNS record for your Droplet
        1. In the Digital Ocean UI, navigate to `Droplets -> <the-droplet>`
        2. Take note of the `ipv4` IP address displayed at the top
        3. However you do this, create a `A` DNS record to associate a root/sub-domain with your Droplet IP address

  You will need to have a domain to create an A record. If you have one hosted somewhere, such as a personal website, you can go to the area where they manage the DNS records (A and CNAME, etc.) and add an A record to a new subdomain, such as, digitalocean.johndoe.com and point it to the ipv4 IP addresss on your Droplet.

  Once that is set up, you will enter that full domain (i.e. `digitalocean.johndoe.com) in step 9 below to generate the certificate.

    2. Generate the certificate
        1. In the Digital Ocean UI, navigate to `Droplets -> <the-droplet>`
        2. Click the `Console []` link on the right side (it's a blue link at the top right)
        3. At the `elastic login:` prompt, type `ubuntu` and hit `ENTER`
        4. At the `Password:` prompt, type `password` and hit `ENTER`
        5. Type `sudo ./get-ssl-certificate` and hit `ENTER`, type `password` and hit `ENTER`
        6. Enter an email address to associate with your certificate
        7. Type `A` then `ENTER` to agree to the terms of service
        8. Specify whether you want to share your email address with the EFF
        9. Enter the name of the root/sub-domain for which you created the `A` record associated with your Droplet IP address
        10. Restart Elasticsearch so that it will use the new certificate by executing `sudo systemctl restart elasticsearch`


5. Check that Elasticsearch is accessible via HTTPS

    1. In a web browser, surf on over to: `https://<the-root/sub-domain-you-created>:9200` and you should see something like this:

    ![Screenshot from 2020-07-16 16-21-18](https://user-images.githubusercontent.com/585182/87718795-6ad05180-c780-11ea-909e-87f5f6c9ef21.png)

    It's reporting a `security_exception` because the server is configured to prevent anonymous, public users from accessing things they shouldn't. You'll see a more friendly response at: `https://<the-root/sub-domain-you-created>:9200/_search`


6. Generate your Elasticsearch passwords

    In order to securely administer your Elasticsearch server, you'll need to generate passwords for the built-in Elasticsearch users.

    If necessary, open a console window:

        1. In the Digital Ocean UI, navigate to `Droplets -> <the-droplet>`
        2. Click the `Console []` link on the right side
        3. At the `elastic login:` prompt, type `ubuntu` and hit `ENTER`
        4. At the `Password:` prompt, type `password` and hit `ENTER`

    Execute the command:

    ```
    sudo /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto
    ```

    The script will display the name and newly-generated password for each of the built-in Elasticsearch users - copy these down and save them in a safe place. You will be using the `elastic` user credentials to later administer the server. See: [Creating Your Local Elasticsearch Credentials File](#creating-your-local-elasticsearch-credentials-file)


7. Change the `ubuntu` user password

    Every droplet that someone creates from the provided custom disk image is going to have the same default `ubuntu` user password of `password`. For better security, you should change this to your own, unique password.

    If necessary, open a console window:

        1. In the Digital Ocean UI, navigate to `Droplets -> <the-droplet>`
        2. Click the `Console []` link on the right side
        3. At the `elastic login:` prompt, type `ubuntu` and hit `ENTER`
        4. At the `Password:` prompt, type `password` and hit `ENTER`

   Execute the command:

    ```
    sudo passwd ubuntu
    ```

    The flow looks like this:

    ```
    [sudo] password for ubuntu: <enter-the-current-password-ie-"password">
    New password: <enter-your-new-password>
    Retype new password: <enter-your-new-password>
    passwd: password updated successfully
    ```

## Configure Automatic Elasticsearch Backups

Elasticsearch provides a [snapshot feature](https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-restore.html) that allows you to save the current state of your indices. These snapshots can then be used to restore an instance to a previous state, or to initialize a new instance.

Though there are several options for where/how to store your snapshots, we'll describe doing so using a Digital Ocean Space and the Elasticsearch [repository-s3](https://www.elastic.co/guide/en/elasticsearch/plugins/current/repository-s3.html) plugin. **Note that since we're leveraging the Digital Ocean Spaces S3-compatible API, these same basic steps can be used to alternately configure an AWS S3 bucket for snapshot storage.**


### Configure Elasticsearch to store snapshots on a Digital Ocean Space

1. Choose or create a Digital Ocean Space

    The easiest thing is use the same DO Space that you're already using to store your collection objects to also store your Elasticsearch snapshots. In fact, the `cb:enable_daily_search_index_snapshots` rake task that we detail below assumes this and parses the Space name from the `digital-objects` value of your production config. [By default](https://github.com/CollectionBuilder/collectionbuilder-sa_draft/blob/es-snapshots/Rakefile#L57), the snapshot files will be saved as non-public objects to a `_elasticsearch_snapshots/` subdirectory of the configured Space, which shouldn't interfere with any existing collections.

    If you don't want to use an existing DO Space to store your snapshots, you should create a new one for this purpose.

2. Create a Digital Ocean Space access key

    Elasticsearch will need to specify credentials when reading and writing snapshot objects on the Digital Ocean Space.

    You can generate your Digital Ocean access key by going to your DO account page and clicking on:

    `API -> Spaces access keys -> Generate New Key`

    A good name for this key is something like: `elasticsearch-snapshot-writer`

3. Configure Elasticsearch to access the Space

    This step needs to be completed on the Elasticsearch server instance itself.

    1. Open a console window:

        1. In the Digital Ocean UI, navigate to `Droplets -> <the-droplet>`
        2. Click the `Console []` link on the right side
        3. At the `elastic login:` prompt, type `ubuntu` and hit `ENTER`
        4. At the `Password:` prompt, type `password` (or your updated password) and hit `ENTER`

    2. Run the [configure-s3-snapshots](https://github.com/CollectionBuilder/collectionbuilder-sa_elasticsearch-image/blob/master/files/configure-s3-snapshots) shell script

        Usage:

        `sudo ./configure-s3-snapshots`

        This script will:

        1. Check whether an S3-compatible endpoint has already been configured
        2. Install the `repository-s3` plugin if necessary
        3. Prompt you for your S3-compatible endpoint (see note)
        4. Prompt you for the DO Space access key
        5. Prompt you for the DO Space secret key

        Notes:

        - This script assumes the default S3 repository name of `"default"`. If you plan on executing the `es:create_snapshot_s3_repository` rake task manually (as opposed to the automated `enable_daily_search_index_snapshots` that we detail below) and specifing a non-default repository name, you should specify that name as the first argument to `configure-s3-snapshots`, i.e. `sudo ./configure-s3-snapshots <repository-name>`

        - You can find your DO Space endpoint value by navigating to `Spaces -> <the-space> -> Settings -> Endpoint` in the Digital Ocean UI. Alternatively, if you know which region your Space is in, the [endpoint value is in the format](https://www.digitalocean.com/docs/spaces/resources/s3-sdk-examples/#configure-a-client): `<REGION>.digitaloceanspaces.com`, e.g. `sfo2.digitaloceanspaces.com`

4. Configure a snapshot repository and enable daily snapshots

    The `cb:enable_daily_search_index_snapshots` rake task takes care of creating the Elasticsearch S3 snapshot repository, automated snapshot policy, and tests the snapshot policy to make sure everything's working.

    Usage:

    ```
    rake cb:enable_daily_search_index_snapshots[<profile-name>]
    ```

    Notes:

    - This task only targets remote production (not local development) Elasticsearch instances, so you must specify an Elasticsearch credentials profile name.
    - This task assumes that you want to use all of the default snapshot configuration values which includes using the same Digital Ocean Space that you've configured in the `digital-objects` value of your production config to store your snapshot files. If you want to use a different repository name, DO Space, or snapshot schedule other than daily, you'll have to run the `es:create_snapshot_s3_repository`, `es:create_snapshot_policy`, and `es:execute_snapshot_policy` rake tasks manually.


## Creating Your Local Elasticsearch Credentials File<a id="creating-your-local-elasticsearch-credentials-file"></a>

After generating passwords for your built-in Elasticsearch users, the ES-related rake tasks will need access to these usernames / passwords (namely that of the `elastic` user) in order to communicate with the server. This is done by creating a local Elasticsearch credentials file.

By default, the tasks will look for this file at: `<user-home>/.elasticsearch/credentials`. If you want to change this location, you can do so [here](https://github.com/CollectionBuilder/collectionbuilder-sa_draft/blob/master/Rakefile#L14).

This credentials file must formatted as YAML as follows:

```
users:
  <profile-name>:
    username: <elasticsearch-username>
    password: <elasticsearch-password>
```

Here's a template that works with the other examples in this documentation, requiring only that you fill in the `elastic` user password:

```
users:
  PRODUCTION:
    username: elastic
    password: <password>
```


## Updating `data/config-search.csv` For An Existing Elasticsearch Index

The search configuration in `config-search.csv` (which is generated by the `cb:generate_search_config` rake task) is used by the `cb:generate_search_index_settings` rake task to generate an Elasticsearch index settings file which the `es:create_index` rake task then uses to create a new Elasticsearch index. If you need to make changes to `config-search.csv` after the index has already been created, you will need to synchronize these changes to Elasticsearch in order for the new configuration to take effect.

While there are a number of ways to achieve this (see: [Index Aliases and Zero Downtime](https://www.elastic.co/guide/en/elasticsearch/guide/current/index-aliases.html#index-aliases)), the easiest is to:

1. Delete the existing index by executing the `es:delete_index` rake task. See `es:create_index` for how to specify a user profile name if you need to target your production Elasticsearch instance. Note that `es:delete_index` automatically [invokes `es:update_directory_index`](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/elasticsearch.rake#L154) to remove the deleted index from any existing directory.

2. Execute the `cb:generate_collection_search_index_settings` and `es:create_index` rake tasks to create a new index using the updated `config-search.csv` configuration 

3. Execute the `es:load_bulk_data` rake task to load the documents into the new index


## Cross-Collection Search

### The `directory_` Index

Cross-collection search is made possible by the addition of a special `directory_` index on the Elasticsearch instance that stores information about the available collection indices.

The documents in `directory_` comprise the fields: `index`, `doc_count`, `title`, `description`

Here's an example Elasticsearch query that returns two documents from a `directory_` index:

```
curl --silent  https://<elasticsearch-host>:9200/directory_/_search?size=2 | jq
{
  "took": 0,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 3,
      "relation": "eq"
    },
    "max_score": 1,
    "hits": [
      {
        "_index": "directory_",
        "_type": "_doc",
        "_id": "pg1",
        "_score": 1,
        "_source": {
          "index": "pg1",
          "doc_count": "342",
          "title": "The University of Idaho Campus Photograph Collection",
          "description": "The University of Idaho Campus Photograph Collection contains over 3000 historical photographs of the UI Campus from 1889 to the present."
        }
      },
      {
        "_index": "directory_",
        "_type": "_doc",
        "_id": "uiext",
        "_score": 1,
        "_source": {
          "index": "uiext",
          "doc_count": "253",
          "title": "Agricultural Experiment & UI Extension Publications",
          "description": "A collaboration between the Library and University of Idaho Extension, the University of Idaho Extension and Idaho Agricultural Experiment Station Publications collection features over 2000 publications that serve as the primary source for practical, research-based information on Idaho agriculture, forestry, gardening, family and consumer sciences, and other to links."
        }
      }
    ]
  }
}
```

The site-specific search page queries this index to collect information about whether there are additional collections available to search.
The cross-collection search page queries this index in order to populate its list of available indices to search against.

### Creating the `directory_` Index

Use the [es:create_directory_index](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/elasticsearch.rake#L134) rake task to create the `directory_` index on your Elasticsearch instance.

Note that the `es:create_directory_index` task operates directly on the Elasticsearch instance and has no dependency on the collection-specific codebase in which you execute it.

Local development usage:
```
rake es:create_directory_index
```

To target your production Elasticsearch instance, you must specify a user profile name argument:
```
rake es:create_directory_index[<profile-name>]
```

For example, to specify the user profile name "PRODUCTION":
```
rake es:create_directory_index[PRODUCTION]
```

### Updating the `directory_` Index

Use the [es:update_directory_index](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/main/rakelib/elasticsearch.rake#L154) rake task to update the `directory_` index to reflect the current state of collection indices on the Elasticsearch instance. Note that the [es:create_index](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/elasticsearch.rake#L134) and [es:delete_index](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/elasticsearch.rake#L227) tasks automatically invoke `es:update_directory_index`.

The `es:update_directory_index` task works by querying Elasticsearch for a list of all available indices that it uses to update the `directory_` index documents by either generating new documents for unrepresented collection indices, or by removing documents that represent collection indices that no longer exist.

Note that the `es:update_directory_index` task operates directly on the Elasticsearch instance and has no dependency on the collection-specific codebase in which you execute it.

Local development usage:
```
rake es:update_directory_index
```

To target your production Elasticsearch instance, you must specify a user profile name argument:
```
rake es:update_directory_index[<profile-name>]
```

For example, to specify the user profile name "PRODUCTION":
```
rake es:update_directory_index[PRODUCTION]
```


## Manually building the project<a id="manually-building-the-project"></a>

The following section provides details on how to manually execute and customize each step of the project build process.

### 0. The `_data/collections` directory structure

During the build process, all generated and downloaded collection-specific files will be stored in collection-specific subdirectories of `_data/collections`.
This tree has the structure:

```
└── _data
    └── collections
        ├── <COLLECTION_URL_FORMATTED_AS_FILENAME>
        │   ├── collection-metadata.json
        │   ├── elasticsearch
        │   │   ├── bulk_data.jsonl
        │   │   └── index_settings.json
        │   ├── extracted_pdfs_text
        │   │   ├── <PDF_URL_FORMATTED_AS_FILENAME>.txt
        │       └── ...
        │   ├── objects-metadata.json
        │   └── pdfs
        │       ├── <PDF_URL_FORMATTED_AS_FILENAME>
        │       └── ...
        └── ...
```


### 1. Generate Collections Metadata

Use the `cb:generate_collections_metadata` rake task to generate a final metadata file for each configured collection in `_data/config-collections.csv`. If there are any required fields unspecified in `config-collection.csv`, an attempt will be made to retrieve these values by reading the JSON-LD data embedded in the response from the `homepage_url`. If any required values remain unsatisfied, you will be prompted for manual input of these values.

This step will generate the `_data/collections/<COLLECTION_URL_FORMATTED_AS_FILENAME>/collection-metadata.json` files.

Usage:
```
rake cb:generate_collections_metadata
```

### 2. Download Collections Object Metadata

Use the `cb:download_collections_objects_metadata` rake task to download each collection's object metadata JSON file from either the `objects_metadata_url` specified in `config-collections.csv` or from the default website path of `/assets/data/metadata.json` as defined by the [$COLLECTIONBUILDER_JSON_METADATA_PATH variable in `rakelib/lib/constants.rb`](https://github.com/CollectionBuilder/collectionbuilder-elasticsearch/blob/29df8f39cc2f0d08e0b150561f78ad4a6fb524a3/rakelib/lib/constants.rb#L157)

This step will generate the `_data/collections/<COLLECTION_URL_FORMATTED_AS_FILENAME>/bjects-metadata.json` files.

Usage:
```
rake cb:download_collections_objects_metadata
```

### 3. Analyze the Objects Metadata

Use the `cb:analyze_collections_objects_metadata` rake task to analyze the downloaded objects metadata files and display any warnings regrading missing or invalid values.

This step will not generate any files.

Usage
```
rake cb:analyze_collections_objects_metadata
```

An error condition will be indicated by the collection-specific output:
```
**** Analyzing objects metadata for collection: <COLLECTION_URL>

...

Found missing or invalid values for the following REQUIRED fields:
{
  "<FIELD_NAME>": 1
}
Please correct these values on the remote collection site, or edit the local copy at the below location, and try again:
  _data/collections/<COLLECTION_URL_ESCAPED_AS_FILENAME>/objects-metadata.json

```
and the final output line:
```
**** Aborting due to 1 collections with missing or invalid REQUIRED object metadata fields
```

The following help text will also be displayed:

```
**** Some optional and/or required fields that we normally include in the search index documents were found to be missing or invalid.
If your metadata uses non-standard field names, the $OBJECT_METADATA_KEY_ALIASES_MAP configuration variable in rakelib/lib/constants.rb provides a means of mapping our names to yours. Please see the documentation in constants.rb for more information on how to do this.
```

Any required missing or invalid fields must be correctly before continuing on to the next step.


### 4. Generate the Default Search Configuration

Use the `cb:generate_search_config` rake task to automatically generate a default search configuration by analyzing all of the downloaded object metadata files.

This step will generate the `_data/config-search.csv` file.

Usage:
```
rake cb:generate_search_config
```


### 5. Download PDFs (for text extraction)

Use the `cb:download_collections_pdfs` rake task to download all PDFs specified in the object metadata files to the local filesystem for text extraction.

This step will download PDFs to the `_data/collections/<COLLECTION_URL_FORMATTED_AS_FILENAME>/pdfs/` directories.

Usage:
```
rake cb:download_collections_pdfs
```

### 6. Extract PDF Text

Use the `cb:extract_pdf_text` rake task to extract text from the downloaded PDFs.

This step will download PDFs to the `_data/collections/<COLLECTION_URL_FORMATTED_AS_FILENAME>/extracted_pdfs_text/` directories.

Usage:
```
rake cb:extract_pdf_text
```


<span name="generate-the-search-index-data-files"></span>
### 7. Generate the Search Index Data Files

Use the `cb:generate_collections_search_index_data` rake task to generate a search index data file for each collection which includes the object metadata and extracted PDF text.

This step will generate the `_data/collections/<COLLECTION_URL_FORMATTED_AS_FILENAME>/elasticsearch/bulk_data.jsonl` files.

Local development usage:
```
rake cb:generate_collections_search_index_data
```

To target your production Elasticsearch instance, you must specify a user profile name argument:
```
rake cb:generate_collections_search_index_data[<profile-name>]
```

For example, to specify the user profile name "PRODUCTION":
```
rake cb:generate_collections_search_index_data[PRODUCTION]
```

When you specify a user profile name, the task assumes that you want to target the production Elasticsearch instance and will read the connection information from `_config.production.yml` and the username / password for the specified profile from your Elasticsearch credentials file.

See: [Creating Your Local Elasticsearch Credentials File](#creating-your-local-elasticsearch-credentials-file)


### 8. Generate the Search Index Settings Files

Use the `cb:generate_collections_search_index_settings` rake task to generate an Elasticsearch index settings file for each collection based on the previously-generated search configuration.

This step will generate the `_data/collections/<COLLECTION_URL_FORMATTED_AS_FILENAME>/elasticsearch/index_settings.json` files.

Usage:
```
rake cb:generate_collections_search_index_settings
```


### 9. Create the Elasticsearch Directory Index

Use the `es:create_directory_index` rake task to create the `_directory` index that is used to store information about which collection-specific indices exist on the server.

Usage:
```
rake es:create_directory_index
```
_See <a href="#generate-the-search-index-data-files">7. Generate the Search Index Data Files</a> for information on specifying a profile to target non-development environments._

### 10. Create the Elasticsearch Collection Indices

Use the `cb:create_collections_search_indices` rake task to create a search index for each collection using the previously-generated index settings.

Usage:
```
rake cb:create_collections_search_indices
```
_See <a href="#generate-the-search-index-data-files">7. Generate the Search Index Data Files</a> for information on specifying a profile to target non-development environments._

### 11. Load the Collection Data into Elasticsearch

Use the `cb:load_collections_search_index_data` rake task to load the previously-generate search index data files into their corresponding indices.

Usage:
```
rake cb:load_collections_search_index_data
```
_See <a href="#generate-the-search-index-data-files">7. Generate the Search Index Data Files</a> for information on specifying a profile to target non-development environments._
