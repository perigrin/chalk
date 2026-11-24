sub k { $_[1]->(); $_[0] } sub w { my $v=1; my $s=sub { $v=9 }; k($v,$s) } print w(),"\n";
