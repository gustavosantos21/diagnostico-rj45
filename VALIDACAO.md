# Validação da versão 1.0

## Concluído localmente

- Identificação do HP EliteBook 640 G11 e da Intel I219-LM, driver 20.0.3.21.
- Compilação inicial e leitura do estado desconectado.
- Verificações iniciais de interpretação de ausência de link, link de 100 Mb/s e IPv4 automático local.
- Conferência da estrutura retornada por `Find-NetRoute` usando a rota de loopback.

## Bloqueio local

A política corporativa do Microsoft Defender Exploit Guard bloqueou a execução recompilada (evento 1121, regra 01443614-CD74-433A-B99E-2ECDC07BFC25). Nenhuma política foi alterada. A execução final local depende de liberação formal pela TI.

## Pendente antes de considerar a ferramenta homologada

- Verificar interface visual, seleção de adaptador e exportação de relatório em execução liberada.
- Conectar cabo a switch gigabit e confirmar velocidade, IPv4 e gateway.
- Testar ICMP com destino disponível e indisponível.
- Manter Wi-Fi ativo e comprovar que rota incompatível interrompe o teste Ethernet.
- Desconectar e reconectar durante acompanhamento e durante teste.
- Verificar redes sem gateway e com IPv4 manual.
- Validar em outro notebook e adaptador USB Ethernet.

Os testes de integração precisam de rede controlada; a automação no GitHub verifica compilação e interpretação de estados, sem atestar condições elétricas do cabo.
