our %h=(a=>1); sub w { $h{a}=9 } my %c=%h; w(); print "$c{a}\n";
