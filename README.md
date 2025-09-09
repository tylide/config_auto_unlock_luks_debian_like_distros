# 🔐 Configuração Automática de Desbloqueio LUKS no Boot

Este projeto contém um script em **Bash** que configura o desbloqueio automático de partições/discos **LUKS** no Debian/Ubuntu durante o boot, utilizando **keyfiles armazenados de forma segura no initramfs**.  

O objetivo é evitar a necessidade de digitar a senha manualmente no `initramfs` a cada inicialização.

---

## 📋 Pré-requisitos

- Distribuição baseada em **Debian/Ubuntu**
- Pacotes instalados:
  - `cryptsetup`
  - `lsblk` (vem junto com `util-linux`)
  - `initramfs-tools`

Verifique se já possui:
```bash
sudo dpkg -l cryptsetup initramfs-tools
```

Para instalar utilize:
```bash
sudo apt update
sudo apt install -y cryptsetup initramfs-tools util-linux
```

## 🚀 Como usar

1. Baixe e execute
```bash
git clone https://github.com/tylide/config_auto_unlock_luks_debian_like_distros.git
cd config_auto_unlock_luks_debian_like_distros
chmod +x config_auto_unlock_luks.sh
sudo ./config_auto_unlock_luks.sh
```

2. Escolha as partições/discos LUKS
  - O script lista todos os dispositivos criptografados detectados no sistema com informações de:

  - Dispositivo base (/dev/sdXN, /dev/md0, etc.)

  - Mapper (/dev/mapper/...)

  - Pontos de montagem associados

  - Você pode selecionar um ou mais índices (ex.: 0 2).

3. O script fará automaticamente:

  - Criar (ou reutilizar) um keyfile seguro em /etc/keys/luks.key

  - Adicionar a chave ao cabeçalho LUKS (pede senha atual uma vez)

  - Atualizar o /etc/crypttab

  - Ajustar /etc/cryptsetup-initramfs/conf-hook e initramfs.conf

  - Regenerar o initramfs (update-initramfs -u)

4. Reinicie o sistema para validar:
```bash
sudo reboot
```
  - Se tudo estiver correto, o desbloqueio será feito de forma automática no boot 🚀

## ⚠️ Notas de segurança

O keyfile é protegido com permissões restritas (chmod 600 e pasta com chmod 700).

Nunca copie este arquivo para locais acessíveis a usuários comuns.

Se não quiser mais o desbloqueio automático, basta remover a entrada correspondente no /etc/crypttab e atualizar o initramfs:
```bash
  sudo update-initramfs -u
```
