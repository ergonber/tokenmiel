"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Wallet, Menu, X } from "lucide-react";
import { useState } from "react";

const navItems = [
  { href: "/", label: "Inicio" },
  { href: "/catalogo", label: "Catálogo" },
  { href: "/como-funciona", label: "Cómo Funciona" },
  { href: "/status", label: "Estado" },
];

export function Navigation() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [walletConnected, setWalletConnected] = useState(false);

  return (
    <header className="sticky top-4 z-50 mx-4 rounded-full border border-border bg-white/80 backdrop-blur-lg shadow-lg">
      <div className="flex items-center justify-between px-6 py-3">
        <Link href="/" className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary text-white font-bold text-lg">
            T
          </div>
          <span className="text-lg font-bold tracking-tight">TokenMiel</span>
        </Link>

        <nav className="hidden md:flex items-center gap-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "px-4 py-2 rounded-full text-sm font-medium transition-colors",
                pathname === item.href
                  ? "bg-primary/10 text-primary-dark"
                  : "text-muted hover:text-foreground hover:bg-primary/5"
              )}
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="hidden md:flex items-center gap-3">
          <Button
            variant={walletConnected ? "outline" : "default"}
            size="sm"
            onClick={() => setWalletConnected(!walletConnected)}
          >
            <Wallet className="h-4 w-4" />
            {walletConnected ? "0x1234...abcd" : "Conectar Wallet"}
          </Button>
        </div>

        <button
          className="md:hidden p-2 rounded-full hover:bg-primary/10"
          onClick={() => setMobileOpen(!mobileOpen)}
        >
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {mobileOpen && (
        <div className="md:hidden border-t border-border px-4 py-3 space-y-2">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              onClick={() => setMobileOpen(false)}
              className={cn(
                "block px-4 py-2 rounded-xl text-sm font-medium transition-colors",
                pathname === item.href
                  ? "bg-primary/10 text-primary-dark"
                  : "text-muted hover:text-foreground"
              )}
            >
              {item.label}
            </Link>
          ))}
          <Button
            variant={walletConnected ? "outline" : "default"}
            size="sm"
            className="w-full"
            onClick={() => setWalletConnected(!walletConnected)}
          >
            <Wallet className="h-4 w-4" />
            {walletConnected ? "0x1234...abcd" : "Conectar Wallet"}
          </Button>
        </div>
      )}
    </header>
  );
}
