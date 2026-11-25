our %h=(a=>1); sub f { $h{a}=9 } my @b=(%h, f()); print "@b\n";
