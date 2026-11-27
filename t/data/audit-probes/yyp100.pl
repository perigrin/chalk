my %h=(a=>1,b=>2); my @b=(@h{qw(a b)}, $h{a}=9); print "@b\n";
