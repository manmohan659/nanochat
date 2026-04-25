'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  Plus,
  PanelLeftClose,
  PanelLeftOpen,
  LogOut,
  Trash2,
  Sun,
  Moon,
  ChevronUp,
} from 'lucide-react';
import SamosaLogo from '@/components/svg/SamosaLogo';
import { useChatStore, groupConversations } from '@/store/chatStore';
import { useAuth } from '@/hooks/useAuth';
import { useTheme } from '@/hooks/useTheme';
import clsx from 'clsx';

const MOBILE_BREAKPOINT = 768;

function isMobileViewport() {
  return typeof window !== 'undefined' && window.innerWidth < MOBILE_BREAKPOINT;
}

export default function Sidebar() {
  const { user, logout } = useAuth();
  const { theme, toggle } = useTheme();
  const {
    conversations,
    currentConversationId,
    sidebarOpen,
    toggleSidebar,
    createConversation,
    selectConversation,
    deleteConversation,
    fetchConversations,
  } = useChatStore();

  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const userBtnRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    fetchConversations();
  }, [fetchConversations]);

  // On first mount on a mobile viewport, ensure the sidebar is closed so the
  // user lands directly on the chat area.
  useEffect(() => {
    if (isMobileViewport() && sidebarOpen) {
      toggleSidebar();
    }
    // Run only on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Close the user menu on outside click.
  useEffect(() => {
    if (!menuOpen) return;
    const handler = (e: MouseEvent) => {
      const t = e.target as Node;
      if (
        menuRef.current && !menuRef.current.contains(t) &&
        userBtnRef.current && !userBtnRef.current.contains(t)
      ) {
        setMenuOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [menuOpen]);

  const closeIfMobile = () => {
    if (isMobileViewport() && sidebarOpen) toggleSidebar();
  };

  const handlePickConversation = (id: string) => {
    selectConversation(id);
    closeIfMobile();
  };

  const handleNewConversation = async () => {
    await createConversation();
    closeIfMobile();
  };

  const grouped = groupConversations(conversations);

  return (
    <>
      {/* Mobile-only backdrop. Tap to close. */}
      {sidebarOpen && (
        <button
          type="button"
          aria-label="Close sidebar"
          onClick={toggleSidebar}
          className="fixed inset-0 z-30 bg-black/40 md:hidden"
        />
      )}

      <aside
        className={clsx(
          'flex flex-col bg-cream-light dark:bg-ink-soft border-r border-cream-border dark:border-ink-border overflow-hidden',
          // Mobile: fixed overlay that slides in/out. Width is 280px so the
          // chat area is fully hidden when open, and offscreen when closed.
          'fixed inset-y-0 left-0 z-40 w-[280px] transition-transform duration-300 ease-in-out',
          sidebarOpen ? 'translate-x-0' : '-translate-x-full',
          // Desktop: in-flow sibling that toggles between full and icon-strip.
          'md:relative md:translate-x-0 md:transition-[width] md:duration-300',
          sidebarOpen ? 'md:w-[260px]' : 'md:w-[56px]',
        )}
      >
        <div className="flex items-center justify-between px-3 py-3 border-b border-cream-border dark:border-ink-border">
          <Link
            href="/"
            className={clsx('flex items-center gap-2 overflow-hidden', !sidebarOpen && 'md:hidden')}
          >
            <SamosaLogo size={28} />
            <span className="font-display font-semibold text-base text-gray-900 dark:text-ink-text whitespace-nowrap tracking-tight">
              samosaChaat
            </span>
          </Link>
          <button
            aria-label="Toggle sidebar"
            onClick={toggleSidebar}
            className="p-1.5 rounded-md hover:bg-cream dark:hover:bg-ink-elev text-brown-light dark:text-ink-text-soft"
          >
            {sidebarOpen ? <PanelLeftClose size={18} /> : <PanelLeftOpen size={18} />}
          </button>
        </div>

        {sidebarOpen && (
          <>
            <div className="px-3 py-3">
              <button
                type="button"
                onClick={handleNewConversation}
                className="w-full flex items-center justify-center gap-2 px-3 py-2.5 rounded-full bg-gray-900 dark:bg-ink-text text-white dark:text-ink text-sm font-medium hover:-translate-y-px shadow-[0_6px_20px_rgba(0,0,0,0.18)] transition-all"
              >
                <Plus size={16} />
                New chat
              </button>
            </div>

            <div className="flex-1 overflow-y-auto px-2 nice-scrollbar">
              {conversations.length === 0 ? (
                <div className="flex flex-col items-center justify-center h-full px-4 text-center py-12">
                  <div className="text-3xl mb-3 opacity-30">💬</div>
                  <p className="text-sm text-gray-400 dark:text-ink-text-soft font-medium">No conversations yet.</p>
                  <p className="text-xs text-gray-400 dark:text-ink-text-soft mt-1">Start your first chat!</p>
                </div>
              ) : (
                Object.entries(grouped).map(([group, items]) => {
                  if (items.length === 0) return null;
                  return (
                    <div key={group} className="mb-4">
                      <div className="px-2 mb-1 text-[11px] uppercase tracking-wider text-gray-400 dark:text-ink-text-soft font-medium">
                        {group}
                      </div>
                      <ul className="space-y-0.5">
                        {items.map((c) => (
                          <li key={c.id} className="group relative">
                            <button
                              type="button"
                              onClick={() => handlePickConversation(c.id)}
                              className={clsx(
                                'w-full text-left px-3 py-2 rounded-full text-sm truncate transition-colors pr-9',
                                c.id === currentConversationId
                                  ? 'bg-cream dark:bg-ink-elev text-brown dark:text-ink-text font-medium'
                                  : 'text-gray-700 dark:text-ink-text-soft hover:bg-cream/70 dark:hover:bg-ink-elev/70',
                              )}
                              title={c.title}
                            >
                              {c.title}
                            </button>
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                deleteConversation(c.id);
                              }}
                              className="absolute right-1.5 top-1/2 -translate-y-1/2 p-1 rounded opacity-0 group-hover:opacity-100 hover:bg-cream dark:hover:bg-ink-elev text-gray-400 hover:text-chutney-red transition-all"
                              aria-label={`Delete ${c.title}`}
                            >
                              <Trash2 size={14} />
                            </button>
                          </li>
                        ))}
                      </ul>
                    </div>
                  );
                })
              )}
            </div>

            <div className="relative px-3 py-3 border-t border-cream-border dark:border-ink-border">
              <button
                ref={userBtnRef}
                type="button"
                onClick={() => setMenuOpen((v) => !v)}
                aria-haspopup="menu"
                aria-expanded={menuOpen}
                className="w-full flex items-center gap-2 p-1.5 rounded-lg hover:bg-cream dark:hover:bg-ink-elev transition-colors"
              >
                <div className="h-9 w-9 rounded-full bg-gradient-to-br from-saffron to-gold text-white flex items-center justify-center text-sm font-semibold shadow-sm">
                  {(user?.name ?? 'G')[0].toUpperCase()}
                </div>
                <div className="flex-1 min-w-0 text-left">
                  <div className="text-sm font-medium text-gray-800 dark:text-ink-text truncate">
                    {user?.name ?? 'Guest'}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-ink-text-soft truncate">
                    {user?.email ?? 'Not signed in'}
                  </div>
                </div>
                <ChevronUp
                  size={14}
                  className={clsx(
                    'text-gray-400 dark:text-ink-text-soft transition-transform',
                    !menuOpen && 'rotate-180',
                  )}
                />
              </button>

              {menuOpen && (
                <div
                  ref={menuRef}
                  role="menu"
                  className="absolute bottom-full left-3 right-3 mb-2 rounded-xl border border-cream-border dark:border-ink-border bg-white dark:bg-ink-soft shadow-lg overflow-hidden"
                >
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      toggle();
                      setMenuOpen(false);
                    }}
                    className="w-full flex items-center gap-2 px-3 py-2.5 text-sm text-gray-700 dark:text-ink-text hover:bg-cream/70 dark:hover:bg-ink-elev/70 transition-colors"
                  >
                    {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
                    <span>{theme === 'dark' ? 'Light mode' : 'Dark mode'}</span>
                  </button>
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      setMenuOpen(false);
                      logout();
                    }}
                    className="w-full flex items-center gap-2 px-3 py-2.5 text-sm text-chutney-red hover:bg-red-50 dark:hover:bg-red-950/30 transition-colors"
                  >
                    <LogOut size={16} />
                    <span>Log out</span>
                  </button>
                </div>
              )}
            </div>
          </>
        )}
      </aside>
    </>
  );
}
