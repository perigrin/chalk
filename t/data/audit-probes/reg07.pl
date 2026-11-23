our $g=1; sub f { $g=5; 1 } my %h=(a=>$g, b=>f(), c=>$g); print "$h{a}$h{b}$h{c}\n";
