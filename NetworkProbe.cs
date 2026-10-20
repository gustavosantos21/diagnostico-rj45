using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Reflection;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.ComponentModel;

[assembly: AssemblyTitle("Diagnóstico RJ45")]
[assembly: AssemblyDescription("Diagnóstico de portas Ethernet para Windows")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]
[assembly: AssemblyInformationalVersion("1.1.0")]

public class Adapter {
    public string Name, Description, Id, Status, Driver, DriverDate, IPv4, Gateway, Dns, Model, ConfigNote;
    public string Mac, Mask, Dhcp, DhcpServer, LeaseStart, LeaseEnd, DnsSuffix, IPv6;
    public long Speed, Received, Sent, RxErrors, TxErrors, RxDiscarded, TxDiscarded;
    public int Index;
    public override string ToString() { return Name + " — " + Description; }
}
public class Probe {
    static List<Dictionary<string, object>> Query(string query) {
        var list = new List<Dictionary<string, object>>();
        using(var search = new ManagementObjectSearcher(new ManagementScope(@"root\cimv2"), new ObjectQuery(query), new EnumerationOptions { Timeout=TimeSpan.FromSeconds(8) }))
        using(var rows = search.Get()) foreach(ManagementObject row in rows) using(row) {
            var item = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            foreach(PropertyData property in row.Properties) item[property.Name]=property.Value;
            list.Add(item);
        }
        return list;
    }
    static string Field(Dictionary<string,object> row, string name) { return row!=null && row.ContainsKey(name) ? Convert.ToString(row[name]) : ""; }
    static string Lease(Dictionary<string,object> row, string name) { string value=Field(row,name); if(value.Length==0) return ""; try { return ManagementDateTimeConverter.ToDateTime(value).ToString("yyyy-MM-dd HH:mm:ss"); } catch { return "não disponível"; } }
    public static Adapter[] Read() {
        var hardware=new List<Dictionary<string,object>>(); var configs=new List<Dictionary<string,object>>(); var drivers=new List<Dictionary<string,object>>();
        string model="", note="Consulta direta ao Windows";
        try { hardware=Query("SELECT GUID, PhysicalAdapter, InterfaceIndex, PNPDeviceID FROM Win32_NetworkAdapter"); configs=Query("SELECT InterfaceIndex, DHCPEnabled, DHCPServer, DHCPLeaseObtained, DHCPLeaseExpires FROM Win32_NetworkAdapterConfiguration"); model=Field(Query("SELECT Model FROM Win32_ComputerSystem").FirstOrDefault(),"Model"); drivers=Query("SELECT DeviceID, DriverVersion FROM Win32_PnPSignedDriver WHERE DeviceClass='NET'"); }
        catch(Exception e) { note="Metadados WMI parcialmente indisponíveis: "+e.Message; }
        var adapters=new List<Adapter>();
        foreach(var nic in NetworkInterface.GetAllNetworkInterfaces()) {
            if(nic.NetworkInterfaceType!=NetworkInterfaceType.Ethernet && nic.NetworkInterfaceType!=NetworkInterfaceType.GigabitEthernet && nic.NetworkInterfaceType!=NetworkInterfaceType.FastEthernetT && nic.NetworkInterfaceType!=NetworkInterfaceType.FastEthernetFx) continue;
            var device=hardware.FirstOrDefault(x=>Field(x,"GUID").Trim('{','}').Equals(nic.Id.Trim('{','}'),StringComparison.OrdinalIgnoreCase));
            if(device!=null && !String.Equals(Field(device,"PhysicalAdapter"),"True",StringComparison.OrdinalIgnoreCase)) continue;
            var a=new Adapter {Name=nic.Name,Description=nic.Description,Id=nic.Id,Status=nic.OperationalStatus.ToString(),Speed=nic.Speed,Model=model,ConfigNote=note,Mac=BitConverter.ToString(nic.GetPhysicalAddress().GetAddressBytes())};
            var driver=drivers.FirstOrDefault(x=>Field(x,"DeviceID")==Field(device,"PNPDeviceID")); a.Driver=Field(driver,"DriverVersion");
            try {
                var properties=nic.GetIPProperties(); var v4=properties.GetIPv4Properties(); a.Index=v4==null?0:v4.Index;
                var config=configs.FirstOrDefault(x=>Field(x,"InterfaceIndex")==a.Index.ToString());
                a.Dhcp=v4==null?"não disponível":(v4.IsDhcpEnabled?"habilitado":"desabilitado / manual");
                a.DhcpServer=Field(config,"DHCPServer"); a.LeaseStart=Lease(config,"DHCPLeaseObtained"); a.LeaseEnd=Lease(config,"DHCPLeaseExpires");
                var addresses=properties.UnicastAddresses.Where(x=>x.Address.AddressFamily==AddressFamily.InterNetwork).OrderBy(x=>x.Address.ToString().StartsWith("169.254.")?1:0).ToArray();
                a.IPv4=String.Join(", ",addresses.Select(x=>x.Address.ToString())); a.Mask=String.Join(", ",addresses.Select(x=>x.IPv4Mask.ToString()));
                a.IPv6=String.Join(", ",properties.UnicastAddresses.Where(x=>x.Address.AddressFamily==AddressFamily.InterNetworkV6).Select(x=>x.Address.ToString()));
                a.Gateway=String.Join(", ",properties.GatewayAddresses.Where(x=>x.Address.AddressFamily==AddressFamily.InterNetwork).Select(x=>x.Address.ToString()));
                a.Dns=String.Join(", ",properties.DnsAddresses.Select(x=>x.ToString())); a.DnsSuffix=properties.DnsSuffix;
                var stats=nic.GetIPv4Statistics(); a.Received=stats.BytesReceived; a.Sent=stats.BytesSent; a.RxErrors=stats.IncomingPacketsWithErrors; a.TxErrors=stats.OutgoingPacketsWithErrors; a.RxDiscarded=stats.IncomingPacketsDiscarded; a.TxDiscarded=stats.OutgoingPacketsDiscarded;
            } catch(Exception e) { a.ConfigNote+="; configuração/contadores incompletos: "+e.Message; }
            adapters.Add(a);
        }
        return adapters.ToArray();
    }
    public static string Assessment(Adapter a) {
        if (a.Status != "Up") return "SEM LINK — confira cabo, encaixe e equipamento na outra ponta. Não é possível determinar a causa apenas por esse estado.";
        if (String.IsNullOrEmpty(a.IPv4)) return "LINK ATIVO, SEM IPv4 — verifique DHCP ou configuração manual. Comunicação IPv4 ainda não testada.";
        if (a.IPv4.Split(',').Any(x => x.Trim().StartsWith("169.254."))) return "LINK ATIVO, IPv4 AUTOMÁTICO LOCAL — pode haver ausência de resposta DHCP. Esse endereço também pode permitir comunicação local.";
        if (a.Speed > 0 && a.Speed < 1000000000) return "LINK ATIVO A " + Speed(a.Speed) + " — capacidade observada nesta conexão; pode refletir a outra ponta, configuração ou cabeamento. Não comprova defeito.";
        return "LINK ATIVO — velocidade negociada e configuração disponíveis. Isso não certifica o cabeamento nem comprova comunicação.";
    }
    public static string Report(Adapter a) {
        return "DIAGNÓSTICO RJ45 | " + DateTimeOffset.Now.ToString("yyyy-MM-dd HH:mm:ss zzz") + Environment.NewLine +
            "Computador: " + a.Model + "\r\nAdaptador: " + a.Description + "\r\nInterface: " + a.Name + " (" + a.Index + ")\r\nDriver: " + a.Driver + "\r\nEstado: " + a.Status +
            "\r\nVelocidade negociada: " + (a.Status=="Up"?Speed(a.Speed):"sem link") + "\r\nMAC local: " + Value(a.Mac) + "\r\nConfiguração IP: " + Value(a.ConfigNote) + "\r\nIPv4: " + Value(a.IPv4) + "\r\nMáscara (mesma ordem dos IPv4): " + Value(a.Mask) + "\r\nIPv6: " + Value(a.IPv6) + "\r\nGateway: " + Value(a.Gateway) + "\r\nDNS configurado: " + Value(a.Dns) + "\r\nSufixo DNS: " + Value(a.DnsSuffix) + "\r\nDHCP: " + Value(a.Dhcp) + "\r\nServidor DHCP: " + Value(a.DhcpServer) + "\r\nInício da concessão (hora local): " + Value(a.LeaseStart) + "\r\nFim da concessão (hora local): " + Value(a.LeaseEnd) +
            "\r\n\r\n" + Assessment(a) + "\r\n\r\nCONTADORES ACUMULADOS DO ADAPTADOR (não são medições do cabo):\r\nRecebidos: " + a.Received + " bytes | enviados: " + a.Sent + " bytes\r\nErros RX/TX: " + a.RxErrors + "/" + a.TxErrors + "\r\nDescartes RX/TX: " + a.RxDiscarded + "/" + a.TxDiscarded +
            "\r\n\r\nRECURSOS FÍSICOS NÃO DISPONÍVEIS NESTA VERSÃO:\r\nMapa dos 8 fios, comprimento, distância até falhas, PoE e certificação Cat5e/Cat6/Cat6A.\r\nNão há integração validada de TDR com o driver atual.\r\nVelocidade negociada não é velocidade real de transferência.\r\nDNS é exibido como configuração; resolução de nomes não foi testada.\r\n";
    }
    public static string Value(string s) { return String.IsNullOrWhiteSpace(s) ? "não disponível" : s; }
    public static string Speed(long s) { return s <= 0 ? "sem link / indisponível" : (s / 1000000.0).ToString("0.##") + " Mb/s"; }
    public static string Test(Adapter a, string target, Action<string> progress) {
        IPAddress ip;
        if (!IPAddress.TryParse(target, out ip) || ip.AddressFamily != AddressFamily.InterNetwork) throw new Exception("Informe um endereço IPv4, por exemplo o gateway da rede.");
        target = ip.ToString();
        string source = (a.IPv4 ?? "").Split(',')[0].Trim();
        IPAddress sourceIP;
        if (a.Status != "Up" || !IPAddress.TryParse(source, out sourceIP)) throw new Exception("Conecte o cabo e aguarde um endereço IPv4 na Ethernet selecionada.");
        source = sourceIP.ToString();
        int success = 0; var latencies=new List<uint>();
        var log = new StringBuilder();
        log.AppendLine("\r\nTESTE ICMP | destino " + target + " | origem " + source + " | " + DateTimeOffset.Now.ToString("o"));
        for (int n = 1; n <= 10; n++) {
            NativeNetwork.VerifyRoute(sourceIP,ip,a.Index);
            uint latency; uint code=NativeNetwork.Echo(sourceIP,ip,out latency);
            bool ok=code==0;
            if (ok) {success++;latencies.Add(latency);}
            string line = "Pacote " + n + "/10: " + (ok ? "resposta em " + latency + " ms" : "sem resposta bem-sucedida (código Windows " + code + ")");
            log.AppendLine(line); progress(line);
            System.Threading.Thread.Sleep(200);
        }
        log.AppendLine("Respostas: " + success + "/10 | ausência de resposta: " + ((10-success)*10) + "%.");
        if(latencies.Count>0) log.AppendLine("Latência mín/média/máx: "+latencies.Min()+" / "+latencies.Average(x=>(double)x).ToString("0.0")+" / "+latencies.Max()+" ms.");
        log.AppendLine("Ausência de resposta pode ser bloqueio ICMP, destino indisponível ou falha de rede; não identifica sozinha defeito no cabo.");
        return log.ToString();
    }
    [STAThread] public static void Main(string[] args) {
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        if (args.Contains("--self-test") || args.Contains("--unit-test")) {
            try {
                if (!Assessment(new Adapter { Status="Disconnected" }).StartsWith("SEM LINK")) throw new Exception("Estado desconectado");
                if (!Assessment(new Adapter { Status="Up", IPv4="10.0.0.2", Speed=100000000 }).StartsWith("LINK ATIVO A 100")) throw new Exception("Link de 100 Mb/s");
                if (!Assessment(new Adapter { Status="Up", IPv4="169.254.1.1" }).Contains("AUTOMÁTICO")) throw new Exception("IPv4 local");
                if (!Assessment(new Adapter { Status="Up", IPv4="" }).StartsWith("LINK ATIVO, SEM")) throw new Exception("Sem IPv4");
                if (!Assessment(new Adapter { Status="Up", IPv4="10.0.0.2", Speed=1000000000 }).StartsWith("LINK ATIVO —")) throw new Exception("Link gigabit");
                bool invalidRejected=false;
                try { Test(new Adapter(), "destino-invalido", s=>{}); } catch(Exception) { invalidRejected=true; }
                if (!invalidRejected) throw new Exception("Destino inválido foi aceito");
                if(args.Contains("--unit-test")) { Environment.ExitCode=0; return; }
                var loopback=NetworkInterface.GetAllNetworkInterfaces().First(x=>x.NetworkInterfaceType==NetworkInterfaceType.Loopback);
                NativeNetwork.VerifyRoute(IPAddress.Loopback,IPAddress.Loopback,loopback.GetIPProperties().GetIPv4Properties().Index);
                uint loopLatency; if(NativeNetwork.Echo(IPAddress.Loopback,IPAddress.Loopback,out loopLatency)!=0) throw new Exception("Falha ICMP loopback");
                var adapters = Read();
                Console.WriteLine("Verificações de interpretação: OK\r\nAdaptadores Ethernet encontrados: " + adapters.Length + "\r\n\r\n" + String.Join("\r\n", adapters.Select(Report)));
                Environment.ExitCode=0;
            } catch (Exception e) { Console.Error.WriteLine(e.Message); Environment.ExitCode=1; }
            return;
        }
        var form = new MainForm();
        Application.Run(form);
    }
}

public class MainForm : Form {
    public bool IsBusy { get { return busy; } }
    ComboBox adapters = new ComboBox(); TextBox target = new TextBox(); TextBox report = new TextBox(); Label status = new Label();
    Button refresh = new Button(), test = new Button(), save = new Button(); CheckBox monitor = new CheckBox();
    System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer(); bool busy; string lastId; string lastState; int transitions;
    public MainForm() {
        Text="Diagnóstico RJ45 1.1.0 — Portátil"; Width=1060; Height=790; MinimumSize=new Size(850,650); StartPosition=FormStartPosition.CenterScreen;
        Font=new Font("Segoe UI",10); BackColor=Color.FromArgb(241,245,249);
        var layout=new TableLayoutPanel { Dock=DockStyle.Fill, Padding=new Padding(24), ColumnCount=1, RowCount=7 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute,52)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,38)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,44)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,46)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,58)); layout.RowStyles.Add(new RowStyle(SizeType.Percent,100)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,30)); Controls.Add(layout);
        layout.Controls.Add(new Label { Text="RJ45  /  Diagnóstico de ponto de rede", Dock=DockStyle.Fill, Font=new Font("Segoe UI",20,FontStyle.Bold), ForeColor=Color.FromArgb(15,45,75) });
        layout.Controls.Add(new Label { Text="Consultas diretas ao Windows • DHCP, endereçamento e comunicação • sem logs automáticos", Dock=DockStyle.Fill });
        adapters.Dock=DockStyle.Fill; adapters.DropDownStyle=ComboBoxStyle.DropDownList; layout.Controls.Add(adapters);
        var actions=new FlowLayoutPanel { Dock=DockStyle.Fill };
        refresh.Text="Atualizar"; test.Text="Testar IPv4"; save.Text="Salvar relatório";
        foreach(var b in new [] {refresh,test,save}) { b.AutoSize=true; b.Height=33; actions.Controls.Add(b); }
        monitor.Text="Acompanhar link (8 s)"; monitor.AutoSize=true; monitor.Margin=new Padding(16,8,0,0); actions.Controls.Add(monitor); layout.Controls.Add(actions);
        var destination=new FlowLayoutPanel { Dock=DockStyle.Fill }; destination.Controls.Add(new Label { Text="Destino IPv4:", AutoSize=true, Margin=new Padding(0,9,8,0) }); target.Width=170; destination.Controls.Add(target); destination.Controls.Add(new Label { Text="Em branco: gateway. 10 pacotes; rota confirmada pela Ethernet.",AutoSize=true, Margin=new Padding(12,9,0,0) }); layout.Controls.Add(destination);
        report.Multiline=true; report.ReadOnly=true; report.ScrollBars=ScrollBars.Vertical; report.Dock=DockStyle.Fill; report.Font=new Font("Consolas",10); report.BackColor=Color.White; report.Text="Conecte o cabo ao notebook e a um switch ou roteador ligado.\r\nClique em Atualizar para ler a porta RJ45.\r\n\r\nA ferramenta verifica link e comunicação; não certifica o cabo."; layout.Controls.Add(report);
        status.Dock=DockStyle.Fill; status.Text="Portátil: resultados em memória. Salve um relatório somente se desejar."; layout.Controls.Add(status);
        refresh.Click+=async (s,e)=>await RefreshData(); test.Click+=async (s,e)=>await TestData();
        adapters.SelectedIndexChanged+=(s,e)=>ShowAdapter(); save.Click+=(s,e)=> { using(var dialog=new SaveFileDialog { Filter="Relatório de texto (*.txt)|*.txt",FileName="diagnostico-rj45-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+".txt" }) if(dialog.ShowDialog()==DialogResult.OK) {try {File.WriteAllText(dialog.FileName,report.Text,Encoding.UTF8);} catch(Exception error) {MessageBox.Show(this,error.Message,"Não foi possível salvar",MessageBoxButtons.OK,MessageBoxIcon.Warning);} } };
        timer.Interval=8000; timer.Tick+=async (s,e)=> { if(monitor.Checked && !busy) await RefreshData(); }; monitor.CheckedChanged+=(s,e)=> { timer.Enabled=monitor.Checked; }; FormClosed+=(s,e)=>timer.Dispose();
        Shown+=async (s,e)=>await RefreshData();
    }
    void Busy(bool value,string text) { busy=value; refresh.Enabled=test.Enabled=adapters.Enabled=save.Enabled=!value; status.Text=text; }
    void ShowAdapter() {
        var a=adapters.SelectedItem as Adapter; if(a==null) return;
        if(lastId==a.Id && lastState!=null && lastState!=a.Status) transitions++;
        if(lastId!=a.Id) transitions=0;
        lastId=a.Id;lastState=a.Status;
        report.Text=Probe.Report(a)+"\r\nMudanças de estado observadas: "+transitions+" (amostragem a cada atualização; eventos entre amostras podem não ser vistos).\r\n";
    }
    async Task RefreshData() {
        if(busy) return; Busy(true,"Consultando hardware e estado da porta...");
        try { var previous=(adapters.SelectedItem as Adapter); var list=await Task.Run(()=>Probe.Read()); adapters.Items.Clear(); adapters.Items.AddRange(list); var selected=list.FirstOrDefault(a=>previous!=null && a.Id==previous.Id) ?? list.FirstOrDefault(a=>a.Description.Contains("I219-LM")) ?? list.FirstOrDefault(); if(selected!=null) adapters.SelectedItem=selected; else report.Text="Nenhum adaptador Ethernet físico foi encontrado."; status.Text="Atualizado às "+DateTime.Now.ToString("HH:mm:ss")+". Link ativo não equivale a cabo certificado."; }
        catch(Exception e) { status.Text="Falha ao consultar: "+e.Message; } finally { Busy(false,status.Text); }
    }
    async Task TestData() {
        if(busy) return; var a=adapters.SelectedItem as Adapter; if(a==null) return;
        string id=a.Id; Busy(true,"Atualizando a Ethernet antes do teste..."); monitor.Checked=false;
        try {
            var list=await Task.Run(()=>Probe.Read()); a=list.FirstOrDefault(x=>x.Id==id); if(a==null) throw new Exception("O adaptador selecionado não está mais disponível.");
            report.Text=Probe.Report(a); string dest=String.IsNullOrWhiteSpace(target.Text)?(a.Gateway??"").Split(',')[0].Trim():target.Text.Trim();
            var progress=new Progress<string>(text=>status.Text=text);
            var result=await Task.Run(()=>Probe.Test(a,dest,text=>((IProgress<string>)progress).Report(text))); report.AppendText(result); status.Text="Teste concluído.";
        } catch(Exception e) { report.AppendText("\r\nTeste interrompido: "+e.Message+"\r\n"); status.Text="Teste não concluído. Consulte o relatório."; } finally { Busy(false,status.Text); }
    }
}
