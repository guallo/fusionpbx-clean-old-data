# fusionpbx-clean-old-data

* Based on:
   * - https://github.com/fusionpbx/fusionpbx-install.sh/blob/d24a68080c4c51e839728e6d9ac34f44f68f096c/debian/resources/backup/fusionpbx-maintenance

* Tested on:
   * - FusionPBX 4.5.14 https://github.com/fusionpbx/fusionpbx/tree/2c7753c471ac93ca78ccbaf6acf9960ebf77ab0b
   * - freeswitch 1.10.3~release~15~129de34d84~buster-1~buster+1
   * - Debian GNU/Linux 10 (buster)

## Usage

```bash
$ sudo -H -u www-data bash fusionpbx-clean-old-data.sh \
                                        --days <mininum-age-of-data> \
                                        --domains <all|comma-separated-list> \
                                        [--exclude <comma-separated-list>]
where:
        --days      is the minimum age (in days) the data must has to be cleaned
        --domains   a comma separated list of domains to be cleaned 
                    (e.g 'some.domain.com, another.domain') or the keyword 'all'
                    to select all available domains
        --exclude   can only be used when --domains is 'all' to exclude a comma 
                    separated list of domains of been cleaned
```

## Install cron job to automatically clean old data

```bash
git clone https://github.com/guallo/fusionpbx-clean-old-data.git
cd fusionpbx-clean-old-data/

sudo cp fusionpbx-clean-old-data.sh /etc/
sudo cp fusionpbx-clean-old-data-caller /etc/cron.daily/

sudo chown root:root /etc/fusionpbx-clean-old-data.sh /etc/cron.daily/fusionpbx-clean-old-data-caller
sudo chmod 755 /etc/fusionpbx-clean-old-data.sh /etc/cron.daily/fusionpbx-clean-old-data-caller

cd ..
rm -rf fusionpbx-clean-old-data/

sudo nano /etc/cron.daily/fusionpbx-clean-old-data-caller  # Edit as needed.
```

## Uninstall cron job

```bash
sudo rm -f /etc/fusionpbx-clean-old-data.sh /etc/cron.daily/fusionpbx-clean-old-data-caller
```

## Disable the original `fusionpbx-maintenance` cron-script

```bash
sudo chmod -x /etc/cron.daily/fusionpbx-maintenance
```

## Enable the original `fusionpbx-maintenance` cron-script

```bash
sudo chmod +x /etc/cron.daily/fusionpbx-maintenance
```
