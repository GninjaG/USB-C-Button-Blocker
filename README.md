# USB-C Button Blocker (usb_c_button_blocker)

Módulo KernelSU/Magisk para Android 16/17 que impede botões fantasmas vindos
de um adaptador USB-C para P2 com defeito, mantendo o áudio do DAC.

KernelSU/Magisk module for Android 16/17 that stops phantom buttons coming from
a faulty USB-C to 3.5 mm adapter, without touching the DAC audio.

---

## Português

### O problema

Um adaptador USB-C/P2 com mau contato no pino TRRS manda eventos de tecla
sozinhos. Os que aparecem no aparelho:

| Código | Tecla | Efeito prático |
|---|---|---|
| 114 | VOLUME_DOWN | volume cai do nada |
| 115 | VOLUME_UP | volume sobe do nada |
| 163 | MEDIA_NEXT | pula faixa |
| 164 | MEDIA_PLAY_PAUSE | pausa/continua música |
| 165 | MEDIA_PREVIOUS | volta faixa |
| 226 | HEADSETHOOK | atende/desliga chamada |

O módulo bloqueia esses seis comandos quando eles vêm do adaptador. Os botões
físicos do celular (gpio-keys), o volume por Bluetooth (AVRCP) e o áudio do
adaptador continuam funcionando.

### Como funciona

Trabalha em dois níveis.

**1. Desvincula o HID do adaptador (sessão atual)**

Quando o Android detecta um dispositivo USB que tem interface de áudio
(classe 01 ou driver snd-usb-audio) e também interface HID (classe 03), o
módulo desfaz o vínculo da interface HID com o driver usbhid. O kernel
desliga a entrada de teclas desse adaptador na hora; o áudio não é afetado.

- O `service.sh` faz uma varredura no boot e fica esperando eventos em
  `/dev/input` com `inotifyd`. Não existe `while`, `sleep` nem polling.
- O `hotplug.sh` roda a cada evento de criação e repete a varredura.
- Teclado/mouse de boot de um dock composto não são desvinculados.

**2. Keylayout sem as seis teclas (próximos boots)**

O módulo gera arquivos `.kl` em `system/usr/keylayout` copiando o
`Generic.kl` do aparelho com as linhas 114, 115, 163, 164, 165 e 226
comentadas com `#`.

- Para adaptadores USB: `Vendor_xxxx_Product_yyyy.kl`, com os IDs em
  minúsculas e 4 dígitos, no formato que o InputFlinger procura.
- Para jacks analógicos: `Button_Jack.kl`, `Headset_Jack.kl`,
  `Wired_Headset.kl`.
- Dispositivos Bluetooth (bus 0005) nunca ganham arquivo por nome, para não
  afetar o AVRCP.

Arquivo gerado depois do boot vale a partir do próximo reboot. Na sessão
atual, quem segura é o desvínculo do HID.

### Onde cada arquivo roda

| Arquivo | Estágio | O que faz |
|---|---|---|
| `customize.sh` | instalação | gera os `.kl` de jack, aplica permissões e contexto SELinux |
| `post-fs-data.sh` | antes da montagem | só repara o contexto SELinux de `system/`; sem geração, sem sync, sem unbind |
| `service.sh` | late_start | sobe o `inotifyd`, gera os `.kl` e desvincula o HID presente |
| `hotplug.sh` | evento de `/dev/input` | gera os `.kl` e desvincula o HID que acabou de chegar |
| `common.sh` | biblioteca | leitura de sysfs, geração dos `.kl`, unbind, reparo de contexto |

### Instalação

1. Instale o ZIP pelo KernelSU ou Magisk.
2. Reinicie. O adaptador **não** precisa estar conectado durante a instalação.
3. Conecte o adaptador e teste o volume e o play/pause.

Gerar o ZIP de novo:

```sh
sh build_usb_blocker.sh            # grava usb_c_button_blocker.zip
sh build_usb_blocker.sh /tmp/x.zip # caminho de saída opcional
```

Precisa de `sh` POSIX e de `zip` ou `python3`. No Termux:
`pkg install zip`.

### O que confere no aparelho

```sh
logcat -s USBButtonBlocker                       # unbind e falhas
dumpsys input | grep -i KeyLayoutFile            # qual .kl foi lido
ls -Zd /data/adb/modules/usb_c_button_blocker/system
```

O último comando deve mostrar `u:object_r:system_file:s0` na pasta e também
em `system/usr`. Se o módulo não consegue garantir esse contexto, ele
desativa a parte de keylayout de propósito, em vez de arriscar o boot.

### Limites

- No KernelSU atual a pasta `system` só é montada com um metamódulo
  (por exemplo `meta-overlayfs`). Sem ele, só a parte do desvínculo funciona.
- Arquivos `.kl` específicos de `/product`, `/system_ext` ou `/odm` têm
  prioridade sobre `/system`. O módulo só escreve em `/system`.
- O bloqueio vale para USB áudio + HID. Uma porta USB-C não é identificada
  pelo kernel, então qualquer DAC USB com HID entra no mesmo critério.
- Sem `inotifyd` no sistema, a proteção a quente não existe; sobra o
  keylayout e a varredura do boot.

### Se der problema

Safe mode do KernelSU/Magisk ou:

```sh
touch /data/adb/modules/usb_c_button_blocker/disable
```

O keylayout de jack fica ativo mesmo com o módulo desabilitado até você
apagar `/data/adb/modules/usb_c_button_blocker/system`.

---

## English

### The problem

A USB-C to 3.5 mm adapter with a bad TRRS contact sends key events on its
own. The keys affected here:

| Code | Key | What happens |
|---|---|---|
| 114 | VOLUME_DOWN | volume drops |
| 115 | VOLUME_UP | volume rises |
| 163 | MEDIA_NEXT | skips track |
| 164 | MEDIA_PLAY_PAUSE | pauses or resumes |
| 165 | MEDIA_PREVIOUS | goes back |
| 226 | HEADSETHOOK | answers or ends a call |

The module blocks these six when they come from the adapter. The phone's
physical buttons (gpio-keys), Bluetooth volume (AVRCP) and the adapter audio
keep working.

### How it works

It works on two levels.

**1. Unbind the adapter HID (current session)**

When Android sees a USB device with an audio interface (class 01 or the
snd-usb-audio driver) and also a HID interface (class 03), the module unbinds
that HID interface from the usbhid driver. The kernel stops delivering keys
from that adapter right away; audio is not affected.

- `service.sh` does one scan at boot and waits for events on `/dev/input`
  with `inotifyd`. There is no `while`, no `sleep`, no polling.
- `hotplug.sh` runs on each create event and repeats the scan.
- A boot keyboard or mouse inside a composite dock is left alone.

**2. Keylayout without the six keys (next boots)**

The module writes `.kl` files to `system/usr/keylayout`, copied from the
phone's `Generic.kl` with lines 114, 115, 163, 164, 165 and 226 commented out
with `#`.

- USB adapters: `Vendor_xxxx_Product_yyyy.kl`, IDs lowercase with four
  digits, the name format InputFlinger looks for.
- Analog jacks: `Button_Jack.kl`, `Headset_Jack.kl`, `Wired_Headset.kl`.
- Bluetooth devices (bus 0005) never get a name-based layout, so AVRCP is
  untouched.

A file written after boot starts taking effect on the next reboot. For the
current session, the HID unbind is what holds.

### Where each file runs

| File | Stage | What it does |
|---|---|---|
| `customize.sh` | install | writes the jack `.kl` files, sets permissions and SELinux context |
| `post-fs-data.sh` | before mount | only repairs the SELinux context of `system/`; no generation, no sync, no unbind |
| `service.sh` | late_start | starts `inotifyd`, writes the `.kl` files, unbinds the HID already present |
| `hotplug.sh` | `/dev/input` event | writes the `.kl` files and unbinds the HID that just arrived |
| `common.sh` | library | sysfs reading, `.kl` generation, unbind, context repair |

### Install

1. Flash the ZIP from KernelSU or Magisk.
2. Reboot. The adapter does **not** need to be connected during install.
3. Plug the adapter in and test volume and play/pause.

Rebuild the ZIP:

```sh
sh build_usb_blocker.sh            # writes usb_c_button_blocker.zip
sh build_usb_blocker.sh /tmp/x.zip # optional output path
```

Needs a POSIX `sh` and either `zip` or `python3`. On Termux:
`pkg install zip`.

### Checking the device

```sh
logcat -s USBButtonBlocker                       # unbind and failures
dumpsys input | grep -i KeyLayoutFile            # which .kl was loaded
ls -Zd /data/adb/modules/usb_c_button_blocker/system
```

The last command must show `u:object_r:system_file:s0` on the folder and on
`system/usr`. If the module cannot guarantee that context, it disables the
keylayout part on purpose instead of risking the boot.

### Limits

- On current KernelSU the `system` folder is only mounted with a metamodule
  (for example `meta-overlayfs`). Without one, only the unbind works.
- Device-specific `.kl` files in `/product`, `/system_ext` or `/odm` take
  priority over `/system`. The module only writes to `/system`.
- The block applies to USB audio plus HID. The kernel does not identify a
  USB-C port, so any USB DAC with HID matches the same rule.
- Without `inotifyd` on the system there is no hotplug protection; only the
  keylayout and the boot scan remain.

### If something goes wrong

KernelSU/Magisk safe mode, or:

```sh
touch /data/adb/modules/usb_c_button_blocker/disable
```

The jack keylayouts stay active even with the module disabled until you
delete `/data/adb/modules/usb_c_button_blocker/system`.
