sub f { $_[0] = "x"; $_[1] = "y" } my %h=(a=>1,b=>2); f(@h{qw(a b)}); print "$h{a}$h{b}\n";
