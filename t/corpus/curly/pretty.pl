# A pretty printer for nested data, in the style of JSON: hashes with
# their keys sorted, arrays, strings quoted and escaped, numbers bare,
# undef as null; and a round of statistics over the same structure.
use v5.42;

sub quote ($s) {
    my $out = '"';
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        if    ($c eq '"')  { $out .= '\\"' }
        elsif ($c eq "\\") { $out .= "\\\\" }
        elsif ($c eq "\n") { $out .= "\\n" }
        elsif ($c eq "\t") { $out .= "\\t" }
        elsif (ord($c) < 32) { $out .= sprintf("\\u%04x", ord($c)) }
        else { $out .= $c }
    }
    return $out . '"';
}

sub looks_like_number ($v) {
    my $s = "$v";
    return 0 if $s eq '';
    my $digits = 0;
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        next if $i == 0 && $c eq '-';
        next if $c eq '.';
        return 0 unless $c ge '0' && $c le '9';
        $digits++;
    }
    return $digits > 0;
}

sub to_json ($data, $indent = 0) {
    my $pad = "  " x $indent;
    my $inner = "  " x ($indent + 1);
    if (!defined $data) {
        return "null";
    } elsif (ref $data eq 'HASH') {
        return "{}" unless scalar(keys %{ $data });
        my @parts = map { $inner . quote($_) . ": " . to_json($data->{$_}, $indent + 1) } sort keys $data->%*;
        return "{\n" . join(",\n", @parts) . "\n$pad}";
    } elsif (ref $data eq 'ARRAY') {
        return "[]" unless $data->@*;
        my @parts = map { $inner . to_json($_, $indent + 1) } $data->@*;
        return "[\n" . join(",\n", @parts) . "\n$pad]";
    } elsif (looks_like_number($data)) {
        return "$data";
    } else {
        return quote($data);
    }
}

my $config = {
    name    => "curly",
    version => 0.17,
    steps   => [1 .. 5],
    authors => [ { name => "Stevan", role => "design" }, { name => "Fable", role => "build" } ],
    empty   => { list => [], map => {} },
    quoted  => "say \"hi\"\n\tthen go",
    nothing => undef,
    nested  => [[1, [2, [3, [4]]]]],
};

say to_json($config);

my %stats;
sub walk ($d, $depth) {
    $stats{deepest} = $depth if $depth > ($stats{deepest} // 0);
    if (ref $d eq 'HASH') {
        $stats{hashes}++;
        walk($d->{$_}, $depth + 1) for sort keys $d->%*;
    } elsif (ref $d eq 'ARRAY') {
        $stats{arrays}++;
        walk($_, $depth + 1) for $d->@*;
    } else {
        $stats{defined $d ? 'scalars' : 'undefs'}++;
    }
}
walk($config, 0);
say join(", ", map { "$_ $stats{$_}" } sort keys %stats);
