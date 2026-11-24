my %h=(a=>1); sub w { $h{a}=9 } my @v=values %h; w(); print "@v\n";
