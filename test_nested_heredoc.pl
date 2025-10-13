#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::Heredoc;

my $code = q{eval <<\EOE, print $@;
print <<'EOF';
ok 10
EOF

$foo = 'ok 11';
print <<EOF;
$foo
EOF
EOE
};

say "Original code:";
say $code;
say "=" x 60;

my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $code);
$preprocessor->transform();
my $preprocessed = $preprocessor->output;

say "Preprocessed code:";
say $preprocessed;
