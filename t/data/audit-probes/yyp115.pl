my %h=(a=>1); sub f { $h{a}=9 } my @b=(values %h, f()); print "@b\n";
