import type { Metadata } from 'next';
import '../app/globals.css';

export const metadata: Metadata = {
  title: 'Tokenization Platform',
  description: 'Landing page frontend for the tokenization platform connected to the backend.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
