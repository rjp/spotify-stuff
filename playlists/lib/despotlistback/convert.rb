### id2uri ## cargo-culted from lib/despotify.c

EncodeAlphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/";
EncodeHash = {}
EncodeAlphabet.split('').each_with_index {|l,i| EncodeHash[l] = i}

def baseconvert(input, frombase, tobase)
    padlen = 22

    out = ' ' * padlen
    padlen = padlen - 1
    numbers = input.split('').map {|h| EncodeHash[h]}
    len = numbers.size

    loop do
        divide = 0
        newlen = 0

        0.upto(len-1) do |i|
            n = numbers[i]
            divide = divide * frombase + n
            if (divide > tobase) then
                numbers[newlen] = divide / tobase
                divide = divide % tobase

                newlen = newlen + 1
            elsif newlen > 0 then
                numbers[newlen] = 0
                newlen = newlen + 1
            end
        end
        len = newlen
        out[padlen] = EncodeAlphabet[divide]
        padlen = padlen - 1

        break if newlen == 0
    end

    # we might not have used up all 22 characters here
    # remove any prefixed whitespace (spotted by andym)
    return out.strip
end

def id2uri(input)
    return baseconvert(input, 16, 62)
end

def uri2id(input)
    return baseconvert(input, 62, 16)
end
