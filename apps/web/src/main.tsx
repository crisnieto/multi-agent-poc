import React from 'react';
import { createRoot } from 'react-dom/client';
import { LocalDemo } from './pages/LocalDemo';
import { Dashboard } from './pages/Dashboard';
import './style.css';

const real = new URLSearchParams(window.location.search).get('mode') === 'real';
createRoot(document.getElementById('root')!).render(<React.StrictMode>{real ? <Dashboard /> : <LocalDemo />}</React.StrictMode>);
