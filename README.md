# Init Server

This is a script to initialize a new Ubuntu server with the following features:

* Create your own user with sudo privileges
* Change hostname
* Only allow SSH key login
* Root login disabled, password authentication disabled
* Have a random password stored securely at /etc/<new_user>.pass
* Have SSH key copied to authorized_keys so you can log in without a password
* Be hardened with UFW, Fail2Ban and allowed SSH connections(only)
* Have BBR enabled for better network performance
* Have the latest HWE kernel installed
* Have the best mirror selected for package updates
* Have snap removed
* Have CPU performance tuned to 'performance' mode
* Have timezone set to GMT
* Have all unnecessary users removed (Check /etc/passwd for remaining users)
* Have all unnecessary packages removed
* Have the latest updates installed
* Have sysbench installed for performance testing
* Have a final benchmark run to verify CPU performance
* Have a final cleanup of unnecessary packages

## How to use

Fisrt, buy a new Ubuntu server from your favorite provider.

Usually they will give you a root user with a password and SSH key access.

Run the following commands on your **local machine**!

```bash
init_link="https://raw.githubusercontent.com/yourusername/init-server/main/init.sh"
wget $init_link -O init.sh
chmod +x init.sh
```

Then run **on your Local Machine**:

```bash
./init.sh <orig_user> <orig_pass> <server> <new_hostname> <new_user>
```

For example:

```bash
./init.sh root "old_password@" 1.2.3.4 my-new-hostname my-new-user
```

If you prefer use SSH to login, simply provide an empty password:

```bash
./init.sh user "" 1.2.3.4 my-new-hostname user
```
