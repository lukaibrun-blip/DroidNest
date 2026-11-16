# DroidNest

Um launcher dedicado a **um jogo Android por vez**, construído a partir do [Husk](https://github.com/Leviidev/Husk)
(GPL-2.0-or-later). O código do Husk está aqui inteiro; o DroidNest é um target a mais dele.

Abre direto no último jogo escolhido, em tela cheia. **+** importa um APK pelo seletor de arquivos do iOS; tocar num jogo o
torna o principal e o abre na hora; três dedos pressionados por cinco segundos dentro do jogo voltam para a lista.

## Estrutura

| Caminho | O que é |
|---|---|
| `src/app/DroidNest/` | o app: `DroidNestApp.swift` (entrada), `SoloManagerView.swift` (a lista), `SoloPlayer.swift` (o jogo em tela cheia e o gesto de três dedos), `SoloStore.swift` (importação, escolha e JIT), `SoloCore.swift` (as decisões, testáveis), `Info.plist`, ícone |
| `src/app/project.yml` | os targets: `Husk` (intacto) e `DroidNest` (`com.droidnest.app`) com o helper de JIT próprio e o scheme |
| `src/app/Husk/` | o código do Husk, compartilhado pelos dois targets |
| `src/translation-layer*`, `src/ios-jit/`, `src/java-framework/` | o runtime que executa o jogo, o JIT e o Java do Android |
| `docs/07-droidnest.md` | o documento: fluxo, persistência, gesto, o que o iOS permite de JIT, limites |
| `tests/solo/` | as verificações (`./tests/solo/run.sh`, roda no Mac, sem simulador) |
| `scripts/package_droidnest_ipa.sh` | gera `DroidNest.ipa` |
| `scripts/ci_build.sh` | monta as dependências (QEMU, ANGLE, MoltenVK, rppairing) e gera os dois IPAs |

O Husk original continua no alvo `Husk`, com seu bundle id (`com.husk.app`), suas telas e seu ícone: os dois apps instalam
lado a lado.

## Build e IPA

Num Mac com Xcode, `meson`, `ninja`, `pkg-config`, `python3`, `xcodegen`, `qemu-img` e Rust com `aarch64-apple-ios`:

```sh
./scripts/ci_build.sh                      # primeira vez: horas, baixa e compila tudo
./scripts/package_droidnest_ipa.sh         # → ~/Desktop/DroidNest.ipa
./scripts/package_ipa.sh                   # → ~/Desktop/Husk.ipa (o Husk original)
./tests/solo/run.sh                        # as verificações do DroidNest
```

O `.pbxproj` versionado é gerado do `project.yml` pelo `xcodegen` (os scripts regeneram antes de compilar).

## Instalar no iPhone

1. Sideload com SideStore, AltStore ou TrollStore (iOS 15.5+). O IPA não é assinado para a App Store: ele precisa de
   `get-task-allow` para o JIT, como o Husk.
2. Abra, importe um APK com **+**, escolha o jogo. Ele abre na hora e, nas próximas vezes, sozinho.
3. JIT: em iOS 26+ o StikJIT embutido liga sozinho depois do pareamento (uma vez) e do LocalDevVPN; instalado por TrollStore,
   ou num aparelho com jailbreak, também não precisa de toque. Entre iOS 16 e 25, sem TrollStore ou jailbreak, o iOS não deixa
   o app anexar o próprio depurador: aí é StikDebug (aberto a cada abertura) ou o modo sem JIT. Os detalhes estão em
   `docs/07-droidnest.md`.

## Licença

GPL-2.0-or-later, a mesma do Husk, porque é o Husk: ele liga o QEMU (GPLv2), então o binário é um trabalho GPLv2 combinado,
com o código-fonte publicado junto, e não vai para a App Store. As licenças do StikJIT (MPL-2.0) e do idevice (MIT) vão dentro
do app. O texto completo está em `LICENSE`, e a discussão em `docs/01-licensing.md`.
