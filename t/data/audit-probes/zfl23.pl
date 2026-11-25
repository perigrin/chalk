my %h=(a=>1); my @b=($h{a}, delete $h{a}, exists $h{a} ? 1 : 0); print "@b\n";
