my %h = (k=>"a"); $h{k} = "$h{k}$h{k}"; print "$h{k}\n";
