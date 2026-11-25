my @a = (1,2,3); my $s = "@a"; { local $" = ""; $s .= "@a"; } { local $" = ", "; $s .= "@a[0,1]"; } my %h = (k => "v"); $s .= "@{[ %h ]}"; print "$s\n";
