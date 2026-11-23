my %h=(a=>1); my %c=%h; my %d=%c; $d{a}=3; print "$h{a}$c{a}$d{a}\n";
