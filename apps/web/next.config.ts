import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  async rewrites() {
    const apiBaseUrl = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://127.0.0.1:3001';

    return [
      {
        source: '/api/:path*',
        destination: `${apiBaseUrl}/:path*`,
      },
    ];
  },
};

export default nextConfig;
