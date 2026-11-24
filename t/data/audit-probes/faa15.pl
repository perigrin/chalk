my $h={a=>{b=>1}}; my $i=$h->{a}; $h->{a}={b=>3}; print $i->{b},"\n";
