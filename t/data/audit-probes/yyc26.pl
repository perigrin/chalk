sub inc { $_[0]++ } my %h=(k=>1); inc($h{k} .= "1"); print "$h{k}\n";
