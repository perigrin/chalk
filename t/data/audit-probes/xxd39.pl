my $h = {a=>{b=>1}}; my $r = \$h->{a}{b}; $h->{a} = {b=>2}; print $$r, $h->{a}{b}, "\n";
