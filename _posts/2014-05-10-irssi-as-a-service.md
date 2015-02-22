---
layout: post
redirect_from: "posts/irssi-as-a-service/"
title: "Running irssi as an interactive service"
---
{% include JB/setup %}



I revamped my server-side IRC setup a bit. I run [irssi](http://www.irssi.org/) there, mainly for logging, so I want it to always run, but only really use it interactively from time to time.

I used to have it running in a separate [tmux](http://tmux.sourceforge.net/) session under my own user, started at boot-time through a crontab entry like

    @reboot tmux -u new-session -d -s irssi /usr/local/bin/irssi

Now I wanted it to

* run under the `irc` user
* be controlled by [runit](http://smarden.org/runit/)
* have all relevant files in `/srv`

This is on a new server running Debian Wheezy but should apply roughly on all UNIXoid systems.

Setting up a service with _runit_ is quite simple, but a bit different to traditional (self-backgrounding) services: There is a `run` script that performs all necessary setup, and then `exec`s the actual program. This is necessary to keep the same PID so the stop/restart functions work properly. Additionally, the service itself must not fork; it should just keep running. Optionally, `stdout` is piped into a dependent `log` service. Should either ever crash or exit, they will be restarted automatically.

The multi-user support in `tmux` is a bit weak, and it lacks any way to synchronously wait for the session to end without attaching to it. I settled on using [screen](http://www.gnu.org/software/screen/) instead– since they (by default) use different shortcuts it is quite convenient to attach to a _screen_ session within my normal _tmux_.

The default Debian `irc` user has a home directory `/var/run/ircd` which does not exist unless `ircd` is installed (which I don't need), so just symlink this:

    ln -s /srv/irc /var/run/ircd

Install the packages:

    apt-get install runit irssi screen

And create the scaffolding for the service:

    mkdir -p /etc/sv/irssi /etc/sv/irssi/log/main /etc/sv/irssi/supervise /etc/sv/irssi/log/supervise
    cat >/etc/sv/irssi/log/run <<EOF
    #!/bin/sh
    exec svlogd -tt ./main
    EOF
    chmod +x /etc/sv/irssi/log/run

Finally, create the `run` script for irssi itself:

    #!/bin/sh

    exec 2>&1

    export HOME=/srv/irc
    export LANG=en_US.UTF-8

    echo "Starting irssi..."
    exec chpst -uirc screen -S irssi -m -D irssi

Explanation of the steps:

* `exec 2>&1`: fold `stderr` into `stdout` so it is captured in the logs (just in case; I do this in all `run`-scripts)
* `export`s: the run script, and subsequently the service, have an almost empty environment. Set `$HOME` so _screen_ can find `.screenrc`, and `$LANG` to work correctly with UTF-8 characters
* `echo`: a marker to track restarts, as screen won't produce any output
* `chpst`: a tool that comes with _runit_ to run the service in the context of another user. Easier to use than su and does not interfere with `runit`
* `screen -S irssi -m -D`: set the session name to `irssi` so there is a fixed name to attach to, start detached but wait until the session finishes

Make it executable (`chmod +x /etc/sv/irssi/run`), and add `/srv/irc/.screenrc` to enable multiuser operation:

    multiuser on
    acladd <your username>

Then enable the service, it will start automatically:

    ln -s ../sv/irssi /etc/service/irssi

and attach to it

    screen -r irc/irssi

To detach without exiting, press `^A d`.
