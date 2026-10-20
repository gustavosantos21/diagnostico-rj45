# Diagnóstico RJ45 1.0.1 — Portátil

Baixe somente **DiagnosticoRJ45.exe** e execute em uma pasta ou pendrive. Não requer instalação, arquivos de configuração ou pasta de logs. Os resultados ficam em memória; exportar relatório é opcional.

Os modos de verificação também não geram arquivos. Não há extração de componentes em pasta temporária. Usa .NET Framework 4.8 e Windows PowerShell 5.1 presentes no Windows compatível.

Inclui leitura de link, velocidade, IPv4, gateway, DNS configurado e contadores, além de teste ICMP com origem e rota verificadas. O perfil inicial é Intel I219-LM; outros adaptadores usam a enumeração padrão do Windows.

Executável sem assinatura digital, sujeito às políticas corporativas de execução. A validação completa da interface e dos testes dentro do aplicativo continua pendente de liberação. Os testes manuais pelas ferramentas do Windows já confirmaram, neste notebook, link a 100 Mb/s e comunicação com o gateway; isso não certifica o cabo.

Não mede mapa de fios, comprimento, PoE ou distância até falhas.
