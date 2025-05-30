
#!/bin/bash
# NixOS Pi Setup Script

set -e

echo "NixOS Pi Configuration Script"
echo "============================"

# Create the configuration directory
sudo mkdir -p /etc/nixos

# Create the flake.nix
sudo tee /etc/nixos/flake.nix > /dev/null << 'EOF'
{
  description = "NixOS Pi Configuration";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  
  outputs = { self, nixpkgs }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        # Hardware configuration will be generated
        ./hardware-configuration.nix
        
        # Main configuration
        ({ config, pkgs, lib, ... }: {
          # System version
          system.stateVersion = "25.05";
          
          # Enable flakes
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          
          # Boot loader for Raspberry Pi
          boot.loader.grub.enable = false;
          boot.loader.generic-extlinux-compatible.enable = true;
          boot.loader.generic-extlinux-compatible.configurationLimit = 2;
          
          # Hostname
          networking.hostName = "nixos";
          
          # Network configuration
          networking.networkmanager.enable = true;
          networking.firewall = {
            enable = true;
            allowedTCPPorts = [ 22 80 64738 ];  # SSH, Pi-hole, Mumble
            allowedUDPPorts = [ 53 64738 ];     # DNS, Mumble
          };
          
          # Enable SSH
          services.openssh = {
            enable = true;
            settings.PasswordAuthentication = true;
          };
          
          # Enable Podman for containers
          virtualisation.podman = {
            enable = true;
            dockerCompat = true;
            defaultNetwork.settings.dns_enabled = true;
          };
          
          # User configuration
          users.users.nixpi = {
            isNormalUser = true;
            description = "NixPi User";
            extraGroups = [ "wheel" "podman" "networkmanager" ];
            initialPassword = "admin";  
            openssh.authorizedKeys.keys = [
              
		"AAAAC3NzaC1lZDI1NTE5AAAAIH/GcEBOq+XMOUcrn2K99e4MGjefO049gaNcywwBsg/T sticker9909@gmail.com"
            ];
          };
          
          # Pi-hole DNS server
          systemd.services.pihole = {
            description = "Pi-hole DNS Server";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = "30s";
              
              # Pull the image before starting
              ExecStartPre = [
                "${pkgs.podman}/bin/podman pull docker.io/pihole/pihole:latest"
                "-${pkgs.podman}/bin/podman stop -t 10 pihole"
                "-${pkgs.podman}/bin/podman rm pihole"
              ];
              
              # Run Pi-hole
              ExecStart = ''
                ${pkgs.podman}/bin/podman run \
                  --name pihole \
                  --hostname pi.hole \
                  --network host \
                  -e TZ='UTC' \
                  -e WEBPASSWORD='admin' \
                  -e INTERFACE='end0' \
                  -e DNSMASQ_LISTENING='all' \
                  -v pihole-etc:/etc/pihole:Z \
                  -v pihole-dnsmasq:/etc/dnsmasq.d:Z \
                  --dns=127.0.0.1 \
                  --dns=1.1.1.1 \
                  --restart=unless-stopped \
                  docker.io/pihole/pihole:latest
              '';
              
              # Stop command
              ExecStop = "${pkgs.podman}/bin/podman stop -t 10 pihole";
            };
          };
          
          # Create Podman volumes for Pi-hole
          systemd.services.pihole-volumes = {
            description = "Create Pi-hole Podman volumes";
            before = [ "pihole.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = [
                "${pkgs.podman}/bin/podman volume create pihole-etc"
                "${pkgs.podman}/bin/podman volume create pihole-dnsmasq"
              ];
            };
          };
          
          # Mumble server (native NixOS container)
          containers.mumble = {
            autoStart = true;
            privateNetwork = true;
            hostAddress = "192.168.100.1";
            localAddress = "192.168.100.2";
            
            forwardPorts = [
              {
                containerPort = 64738;
                hostPort = 64738;
                protocol = "tcp";
              }
              {
                containerPort = 64738;
                hostPort = 64738;
                protocol = "udp";
              }
            ];
            
            config = { config, pkgs, ... }: {
              system.stateVersion = "25.05";
              
              # Mumble server
              services.murmur = {
                enable = true;
                openFirewall = true;
                welcomeText = "Welcome to Mumble on NixOS Pi!";
                serverPassword = "admin";
                bandwidth = 72000;
                users = 50;
                port = 64738;
              };
            };
          };
          
          # System packages
          environment.systemPackages = with pkgs; [
            vim
            git
            htop
            tmux
            podman-compose
          ];
        })
      ];
    };
  };
}
EOF

