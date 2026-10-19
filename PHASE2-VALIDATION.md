# Mês a mês — fase 2 / iOS 1.4.0 (build 5)

## Implementado

- Desbloqueio local opcional com Face ID, Touch ID ou código do aparelho. Ativar e desativar exige confirmação pelo sistema. Não substitui a autenticação da conta.
- Conteúdo coberto sincronamente antes da captura do seletor de aplicativos; a árvore de acessibilidade também fica protegida. Depois de entrar em segundo plano, um novo desbloqueio é exigido quando a proteção está ativa.
- Preferências nativas no Keychain, disponíveis somente com o aparelho desbloqueado e restritas a este dispositivo. Nenhuma senha, token bancário ou posição financeira é copiada para a ponte nativa.
- Ponte limitada ao domínio HTTPS do app e ao frame principal. Janelas de autorização de bancos não recebem a ponte.
- Lembretes locais opcionais de faturas, pagamentos previstos e prazos de metas. Datas e destinos são validados no iOS; limite de 60 pedidos nos próximos 45 dias, agrupados por tipo e data. Conteúdo sem valores, nomes de bancos ou estabelecimentos.
- Notificações são preparadas com a última leitura autenticada do app. Mudanças no banco só cancelam/alteram avisos depois de uma nova leitura. Não há promessa de sincronização em segundo plano nem push remoto.
- Pedidos e avisos entregues são cancelados ao sair ou trocar de conta. Cada aviso pertence a um identificador derivado da conta; tocar em um aviso de outra conta não abre seu conteúdo.
- Perfil → Seu dispositivo: privacidade, lembretes e primeiros passos. Ocultar valores também vale para a consulta offline e não altera cálculos ou exportações.
- Retorno à posição anterior em cada aba, transição discreta com respeito a movimento reduzido e fechamento do teclado ao trocar de página.

## Verificação automatizada

- Testes JavaScript de preferências, ausência de dados privados nos lembretes, agrupamento, quitação de faturas, metas, primeiros passos e mascaramento de valores.
- Swift: origem permitida, rejeição de subframes/origens externas, data e horário, conteúdo genérico, deduplicação e destino.
- Compilação Xcode do executável ARM64 e verificação de versão/identificador no IPA.
- Revisão visual de controles com dados sintéticos, temas claro e escuro e largura de 390 px. A simulação da ponte serve apenas para conferir a interface; não valida Face ID nem entrega real.

## Validação obrigatória em iPhone físico (pendente)

1. Instalar o IPA sobre o existente, abrir com internet e entrar na conta.
2. Em Perfil → Privacidade e lembretes, ativar o desbloqueio. Cancelar uma tentativa, tentar novamente e usar também o código do aparelho. Desativar deve pedir confirmação.
3. Ir para a tela inicial e abrir o seletor de apps: os saldos não devem aparecer. Retornar deve pedir desbloqueio. Repetir bloqueando a tela e fechando o app por completo.
4. Ocultar valores, trocar entre todas as abas e reabrir o app. Conferir também a consulta em modo avião. Desocultar deve restaurar os números.
5. Ativar notificações e usar “Testar notificação”. Sair do app e aguardar o aviso. Tocá-lo deve respeitar o desbloqueio e abrir Movimentações.
6. Negar a permissão, conferir a indicação nos controles e usar Abrir Ajustes. Ativar somente os tipos desejados e mudar horário/antecedência.
7. Sincronizar uma fatura paga e conferir que seu lembrete pendente é retirado. Sair da conta/trocar de conta deve cancelar os avisos anteriores.
8. Nas abas e formulários: conferir teclado, rolagem, menus, voltar à posição anterior e a preferência de movimento reduzido do iOS.
9. Em uma conta nova, seguir a conexão bancária ou o registro manual, planejamento e criação de meta. O progresso deve atualizar sem criar lançamentos de demonstração.

A implementação e a compilação não encerram a fase 2: o aceite dos recursos do sistema depende destes testes no aparelho.
