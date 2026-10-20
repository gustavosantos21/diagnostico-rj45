# Diagnóstico RJ45 1.0

Versão inicial para Windows com seleção de interface Ethernet, leitura de link e velocidade, configuração IPv4, contadores, acompanhamento de conexão e teste ICMP com origem e rota verificadas.

O perfil inicial é HP EliteBook 640 G11 / Intel I219-LM. Outros adaptadores usam os dados padrão do Windows.

**Estado de validação:** a consulta inicial ao hardware foi validada sem cabo. A execução final local está pendente de liberação corporativa e os testes ativos com cabo e switch ainda não foram concluídos. Esta release identifica a versão de desenvolvimento; não representa homologação física ou certificação de cabeamento.

Requer Windows 10/11, .NET Framework 4.8 e Windows PowerShell 5.1. Executável sem assinatura digital. Não mede mapa de fios, comprimento, PoE ou distância até falhas.
