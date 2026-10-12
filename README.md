# Mês a mês para iPhone — projeto iOS, não IPA compilado

Este pacote contém o código-fonte de um contêiner iOS em Swift/UIKit/WebKit para o aplicativo financeiro privado. Ele usa o aplicativo publicado em https://mes-a-mes-financas.rosycream3.chatgpt.site/ e não contém credenciais de Pluggy, Supabase ou OpenAI. Nenhuma demonstração está habilitada na interface.

## Estado da entrega
- O aplicativo web foi adaptado para iPhone, com áreas seguras, navegação inferior, formulários de uma coluna, tipografia nativa e lista paginada em cards.
- O projeto iOS ainda NÃO foi compilado nem executado em iPhone ou simulador. Não há um IPA executável dentro deste pacote.
- Este ambiente de criação é Linux, sem Xcode e sem SDK iOS. Não é possível construir e verificar aqui o binário ARM64 necessário.
- O Sideloadly pode assinar o IPA durante a instalação, mas não compila um projeto Swift. Não envie sua senha Apple ao autor do aplicativo; use-a somente no próprio Sideloadly.

## Gerar o IPA para Sideloadly
1. Em um Mac, instale o Xcode completo com o SDK iOS correspondente ao dispositivo. Para validar no iOS 27, use Xcode 27 com seu SDK iOS 27. Aceite a licença do Xcode e instale os componentes solicitados.
2. Descompacte este pacote e abra `MesAMes.xcodeproj` para inspeção e teste. O alvo mínimo é iOS 17, arquitetura de dispositivo ARM64; o SDK escolhido é o instalado no Xcode.
3. No Terminal, execute `bash build-unsigned-ipa.sh` a partir desta pasta.
4. O script compila o executável e só então cria `build/MesAMes-unsigned.ipa`. Não usa certificado Apple no build.
5. Leve esse IPA ao computador com Sideloadly, selecione seu iPhone, carregue o arquivo e siga o fluxo de assinatura/instalação do Sideloadly.

Alternativamente, configure sua equipe no Xcode, compile e instale diretamente no iPhone. Para distribuição ad hoc ou TestFlight, use o fluxo oficial de assinatura e distribuição do Xcode.

## Gerar sem possuir um Mac (GitHub Actions)
O pacote inclui `.github/workflows/build-ios.yml`. Crie um repositório GitHub e envie o CONTEÚDO desta pasta para a raiz do repositório (incluindo a pasta `.github`). Em Actions, escolha “Gerar IPA para Sideloadly” → Run workflow. O job usa uma máquina macOS com Xcode e gera o artefato `MesAMes-unsigned-IPA` somente se a compilação terminar com sucesso.

A opção `macos-latest` usa a imagem estável disponível no GitHub; ela não garante o SDK Apple mais recente. A opção `xcode-27` depende da disponibilidade da imagem em preview na sua conta. Para testar especificamente iOS 27, confirme nos logs o SDK utilizado. Repositórios privados consomem a franquia de minutos da conta e podem gerar cobrança conforme o plano; este pacote não inicia nenhuma execução nem cria um repositório automaticamente. O workflow ainda NÃO foi executado.

## Validar no iPhone antes de usar como app final
- Login do site privado pelo ChatGPT dentro do WebKit. Provedores de autenticação podem exigir adaptações para navegadores embutidos; o fluxo não foi validado fisicamente.
- Conexão Pluggy, janela de autorização de cada banco, retorno e sincronização. Popups preservam a página original e seu callback.
- Cadastro de entrada, saída, cartão, parcelas, aportes e metas; comparação com os indicadores.
- Teclado, Dynamic Island, indicador de início, rotação, aumento de texto e navegação com VoiceOver.
- Exportação CSV pelo compartilhamento nativo, importação de arquivo e recuperação após perda de rede.
- Profiling pelo Instruments no seu iPhone, com volume real de transações. Não há promessa de ausência de gargalos sem medir no aparelho.

## Instalação imediata como app web
No Safari do iPhone, abra o aplicativo, entre na sua conta e use Compartilhar → Adicionar à Tela de Início → Abrir como App da Web. Este caminho não gera IPA nem passa pelo Sideloadly.

## Limites que permanecem
A chave OpenAI fornecida foi rejeitada e a IA externa está desabilitada; regras locais continuam ativas. Bancos ainda exigem a autorização do titular. Sincronização em segundo plano e reconciliação completa de compras parceladas importadas não estão concluídas. O app depende da internet e não armazena movimentações offline.

## Fontes
- https://sideloadly.io/
- https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
- https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices
- https://support.apple.com/guide/iphone/iphea86e5236/ios
