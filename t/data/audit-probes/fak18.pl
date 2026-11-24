my $r=[1]; my $f=sub { scalar @$r }; $r=[1,2,3]; print $f->(),"\n";
