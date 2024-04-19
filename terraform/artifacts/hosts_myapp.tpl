[lb]
%{ for ip in lb_ip ~}
${ip} domain=odennav.com
%{ endfor ~}

[ws]
%{ for ip in ws_ip ~}
${ip} domain=odennav.com
%{ endfor ~}
