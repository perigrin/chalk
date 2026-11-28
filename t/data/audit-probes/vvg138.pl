my $r = [1,2,3]; my @s = @{$r}[0,1]; my @t = @$r[1,2]; print "@s|@t\n";
