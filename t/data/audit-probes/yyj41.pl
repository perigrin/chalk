our %h=(a=>1,b=>2); sub g1 { join ",", map { "$_$h{$_}" } sort keys %h } sub t { my $v = delete local $h{a}; $v . g1() } print t(), g1(), "\n";
