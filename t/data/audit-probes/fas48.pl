our $x=1; sub n { $x=7 } my %h=(a=>$x, b=>n(), c=>$x); print "$h{a}$h{b}$h{c}\n";
