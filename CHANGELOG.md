# Histórico de versões

## 1.0.1 — 2026-10-20

- Distribuição portátil com um único executável, sem configuração externa ou gravação automática de logs.
- Removida geração de arquivos dos modos de verificação e removido o modo de captura de imagem.
- Relatórios permanecem em memória; exportação apenas por escolha explícita do usuário.
- CI verifica os modos de diagnóstico em uma pasta com somente o executável e detecta arquivos auxiliares criados nessa pasta.


## 1.0.0 — 2026-10-20

- Versão inicial do aplicativo Windows para diagnóstico RJ45.
- Seleção automática da Intel I219-LM e seleção manual de outras interfaces Ethernet físicas.
- Consulta de link, velocidade negociada, configuração IPv4 e contadores do adaptador.
- Teste ICMP com origem e rota validadas pela interface selecionada.
- Acompanhamento de link e exportação de relatório.
- Compilação reproduzível, testes de interpretação e publicação pelo GitHub Actions.

Pendências: testes físicos com cabo conectado, homologação em outros computadores e liberação corporativa do executável. Sem certificação de cabeamento ou integração TDR validada.
