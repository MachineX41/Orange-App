namespace Orange;

/// <summary>Peak, silence, remix and bleep math shared with the macOS audio editor.</summary>
public sealed class AudioBuffer
{
    public AudioBuffer(double sampleRate, IReadOnlyList<float[]> channels)
    {
        SampleRate = sampleRate;
        Channels = channels.Select(channel => channel.ToArray()).ToArray();
    }

    public double SampleRate { get; }
    public float[][] Channels { get; }
    public int ChannelCount => Channels.Length;
    public double Duration => Channels.Length == 0 || Channels[0].Length == 0 ? 0 : Channels[0].Length / SampleRate;
    public float Peak => Channels.Length == 0 ? 0 : Channels.Max(channel => channel.Length == 0 ? 0 : channel.Max(Math.Abs));

    public float[] Mono()
    {
        if (Channels.Length == 0) return [];
        if (Channels.Length == 1) return Channels[0].ToArray();
        var count = Channels[0].Length;
        var mixed = new float[count];
        for (var index = 0; index < count; index++)
        {
            float sum = 0;
            for (var channel = 0; channel < Channels.Length; channel++) sum += Channels[channel][index];
            mixed[index] = sum / Channels.Length;
        }
        return mixed;
    }

    public (double Start, double End) SilenceBounds(double thresholdDb = -45)
    {
        var threshold = (float)Math.Pow(10, thresholdDb / 20);
        var mixed = Mono();
        var window = Math.Max(1, (int)(SampleRate * 0.01));
        int? first = null;
        var last = 0;
        for (var index = 0; index < mixed.Length; index += window)
        {
            var end = Math.Min(index + window, mixed.Length);
            float peak = 0;
            for (var sample = index; sample < end; sample++) peak = Math.Max(peak, Math.Abs(mixed[sample]));
            if (peak >= threshold)
            {
                first ??= index;
                last = end;
            }
        }
        if (first is null) return (0, Duration);
        return (first.Value / SampleRate, last / SampleRate);
    }

    public AudioBuffer Remixed(bool toMono, IReadOnlyList<double> gains)
    {
        var left = (float)(gains.Count > 0 ? gains[0] : 1);
        var right = (float)(gains.Count > 1 ? gains[1] : left);
        if (toMono) return new AudioBuffer(SampleRate, [Scale(Mono(), left)]);
        var l = Channels.Length > 0 ? Channels[0] : [];
        var r = Channels.Length > 1 ? Channels[1] : l;
        return new AudioBuffer(SampleRate, [Scale(l, left), Scale(r, right)]);
    }

    public AudioBuffer NormalizedPeak(double targetDb)
    {
        var current = Decibels(Peak);
        return Gained(targetDb - current);
    }

    public AudioBuffer Gained(double db)
    {
        var factor = (float)Math.Pow(10, db / 20);
        return new AudioBuffer(SampleRate, Channels.Select(channel => Scale(channel, factor, clip: true)).ToArray());
    }

    public AudioBuffer Bleeped((double Start, double End) range, bool tone, double frequency = 1000)
    {
        var output = Channels.Select(channel => channel.ToArray()).ToArray();
        const float level = 0.35f;
        var lower = Frame(range.Start);
        var upper = Frame(range.End);
        if (upper <= lower) return new AudioBuffer(SampleRate, output);
        var fade = Math.Min((int)(SampleRate * 0.004), (upper - lower) / 2);
        foreach (var channel in output)
        {
            for (var index = lower; index < upper && index < channel.Length; index++)
            {
                var position = index - lower;
                var edge = Math.Min(position, upper - 1 - index);
                var envelope = fade > 0 ? Math.Min(1, edge / (float)fade) : 1;
                var value = tone ? level * (float)Math.Sin(2 * Math.PI * frequency * index / SampleRate) : 0;
                channel[index] = channel[index] * (1 - envelope) + value * envelope;
            }
        }
        return new AudioBuffer(SampleRate, output);
    }

    public AudioBuffer Trimmed(double start, double end)
    {
        var lower = Frame(start);
        var upper = Math.Max(lower, Frame(end));
        return new AudioBuffer(SampleRate, Channels.Select(channel =>
        {
            upper = Math.Min(upper, channel.Length);
            return channel[lower..upper];
        }).ToArray());
    }

    public float[] Peaks(int buckets)
    {
        var mixed = Mono();
        if (buckets <= 0 || mixed.Length == 0) return [];
        var size = Math.Max(1, mixed.Length / buckets);
        var peaks = new float[buckets];
        for (var bucket = 0; bucket < buckets; bucket++)
        {
            var start = Math.Min(bucket * size, mixed.Length);
            var end = Math.Min(start + size, mixed.Length);
            float peak = 0;
            for (var index = start; index < end; index++) peak = Math.Max(peak, Math.Abs(mixed[index]));
            peaks[bucket] = Math.Min(1, peak);
        }
        return peaks;
    }

    public void WriteWav(string path)
    {
        var channels = Math.Max(1, Channels.Length);
        var frames = Channels.Length == 0 ? 0 : Channels[0].Length;
        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream);
        var dataBytes = frames * channels * 2;
        writer.Write("RIFF"u8.ToArray());
        writer.Write(36 + dataBytes);
        writer.Write("WAVE"u8.ToArray());
        writer.Write("fmt "u8.ToArray());
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)channels);
        writer.Write((int)SampleRate);
        writer.Write((int)(SampleRate * channels * 2));
        writer.Write((short)(channels * 2));
        writer.Write((short)16);
        writer.Write("data"u8.ToArray());
        writer.Write(dataBytes);
        for (var frame = 0; frame < frames; frame++)
        {
            for (var channel = 0; channel < channels; channel++)
            {
                var sample = channel < Channels.Length && frame < Channels[channel].Length ? Channels[channel][frame] : 0;
                var pcm = (short)Math.Clamp(sample * short.MaxValue, short.MinValue, short.MaxValue);
                writer.Write(pcm);
            }
        }
    }

    public static AudioBuffer ReadWav(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new BinaryReader(stream);
        reader.ReadBytes(4);
        reader.ReadInt32();
        reader.ReadBytes(4);
        short channels = 1;
        var rate = 44100;
        var bits = 16;
        var data = Array.Empty<byte>();
        while (stream.Position + 8 <= stream.Length)
        {
            var id = new string(reader.ReadChars(4));
            var size = reader.ReadInt32();
            if (id == "fmt ")
            {
                reader.ReadInt16();
                channels = reader.ReadInt16();
                rate = reader.ReadInt32();
                reader.ReadInt32();
                reader.ReadInt16();
                bits = reader.ReadInt16();
                if (size > 16) reader.ReadBytes(size - 16);
            }
            else if (id == "data")
            {
                data = reader.ReadBytes(size);
                break;
            }
            else
            {
                reader.ReadBytes(size);
            }
        }
        if (bits != 16) throw new OrangeException(OrangeErrorCode.Unsupported, "WAV");
        var frameSize = channels * 2;
        var frames = data.Length / frameSize;
        var buffers = Enumerable.Range(0, channels).Select(_ => new float[frames]).ToArray();
        var cursor = 0;
        for (var frame = 0; frame < frames; frame++)
        {
            for (var channel = 0; channel < channels; channel++)
            {
                var pcm = BitConverter.ToInt16(data, cursor);
                cursor += 2;
                buffers[channel][frame] = pcm / (float)short.MaxValue;
            }
        }
        return new AudioBuffer(rate, buffers);
    }

    public static double Decibels(float linear) => linear > 0 ? 20 * Math.Log10(linear) : -120;

    int Frame(double seconds) => Math.Clamp((int)(seconds * SampleRate), 0, Channels.Length == 0 ? 0 : Channels[0].Length);

    static float[] Scale(float[] samples, float factor, bool clip = false) =>
        samples.Select(sample =>
        {
            var value = sample * factor;
            return clip ? Math.Clamp(value, -1, 1) : value;
        }).ToArray();
}
