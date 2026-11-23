our %h=(a=>1); sub f { $h{b}=2; 0 } my @c=(%h, f()); print scalar(@c),"\n";
