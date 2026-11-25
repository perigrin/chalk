sub ctx { wantarray ? "l" : defined(wantarray) ? "s" : "v" } my @l=ctx(); my $s=ctx(); print "$l[0]$s", scalar(ctx()), "\n";
