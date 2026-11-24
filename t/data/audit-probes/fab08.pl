my %h=(a=>1,b=>2); my $d=delete $h{a}; my $e=delete $h{zz}; print $d, defined $e?1:0, scalar(%h)?1:0, "\n";
