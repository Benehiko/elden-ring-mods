# Connecting for co-op: LAN or VPN

Co-op runs directly between the players' machines. Each machine listens on
**UDP port 7777**, and nothing gets through a home router from the internet,
so every machine must be able to reach the others directly:

- **Same home network (LAN)?** You are done; check [the firewall](#the-firewall).
- **Friends elsewhere?** Put everyone on one free virtual network with
  [ZeroTier](#zerotier) or [Tailscale](#tailscale). It takes a few minutes,
  once.

When you are connected, the [co-op guide](coop.md) takes over.

## ZeroTier

**One player creates the network** (once):

1. Sign in at [my.zerotier.com](https://my.zerotier.com) (a free account).
2. Press **Create A Network**. Copy its **Network ID**, 16 characters like
   `8056c2e21c000001`, and send it to your friends.

**Every player joins it**, the creator too:

1. Install ZeroTier:

   ```sh
   sudo pacman -S zerotier-one                       # Arch
   curl -s https://install.zerotier.com | sudo bash  # other Linux
   sudo systemctl enable --now zerotier-one          # Linux: start it
   ```

   On macOS, run the installer from
   [zerotier.com/download](https://www.zerotier.com/download/).

2. Join the network:

   ```sh
   sudo zerotier-cli join <network-id>
   ```

   On macOS you can also use the ZeroTier menu-bar icon: **Join New Network**.

**The creator lets everyone in.** On [my.zerotier.com](https://my.zerotier.com),
open the network and scroll to **Members**. Each machine that joined is
listed; tick its **Auth** box. A new network is private, so nobody gets an
address until this is done.

**Every player checks it works:**

```sh
sudo zerotier-cli listnetworks   # your network should say OK, with an address
ping <a friend's ZeroTier address>
```

**Which address is the ZeroTier one?** `ermod-engine coop id` lists every
address this machine has, each with its interface in brackets, so it lists
your home network's address as well. Pick the ZeroTier one in either of two
ways:

- **Match it.** The last column of `sudo zerotier-cli listnetworks` is your
  ZeroTier address, for example `10.147.20.5/24`. Drop the `/24`: the
  `coop id` line with `10.147.20.5` is the one to send. The network page on
  my.zerotier.com shows the same address under **Members**, as
  **Managed IPs**.
- **Read the interface name.** On Linux, ZeroTier's interface starts with
  `zt` (for example `ztabcd1234`). On macOS it starts with `feth` (for
  example `feth956`).

**Do not go by the number.** A ZeroTier network may hand out `10.…`, `172.…`
or `192.168.…` addresses, so its address can look just like a home
network's. Trust the interface name, or the match with `listnetworks`.

```text
Linux:
Address    192.168.1.10      (enp5s0)        ← your home network: not this one
           10.147.20.5       (ztabcd1234)    ← ZeroTier: send this join line

macOS:
Address    192.168.1.23      (en0)           ← your home network: not this one
           192.168.194.177   (feth956)       ← ZeroTier: send this join line
```

With three or more players, every address a joiner names (the host's and
the earlier joiners') is a ZeroTier address: a friend elsewhere cannot reach
your home network's address.

## Tailscale

1. Every player installs [Tailscale](https://tailscale.com/download) and runs
   `sudo tailscale up`.
2. Everyone signs in to the same tailnet, or the owner
   [shares](https://tailscale.com/kb/1084/sharing) their machine with friends.
3. `tailscale ip -4` prints your Tailscale address (`100.…`). In `coop id`
   it is the one on the `tailscale0` interface (on macOS, a `utun`
   interface); send the join line with that address. Ping a friend's to check.

## The firewall

If a machine runs a firewall, let in UDP on port 7777 (on the VPN interface
too, if you use one):

```sh
sudo ufw allow 7777/udp                                   # Linux, ufw
sudo firewall-cmd --add-port=7777/udp --permanent && sudo firewall-cmd --reload   # Linux, firewalld
```

On macOS, if the system asks whether Wine may accept incoming connections,
allow it.

A friend still not getting through? See
[The friend never shows up](coop.md#the-friend-never-shows-up).
