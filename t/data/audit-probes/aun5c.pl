my $d=@ARGV; my @v = grep { $_ } (0, $d); my $r = @v ? 1/$v[0] : "none"; print "$r\n";
